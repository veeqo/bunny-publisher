# frozen_string_literal: true

module BunnyPublisher
  # Enforces mandatory option for message publishing.
  # Catches returned message if they are not routed.
  # Creates queue/binding before re-publishing the same message again.
  # This publisher DUPLICATES the connection for re-publishing messages!
  module Mandatory
    extend ActiveSupport::Concern

    included do
      define_callbacks :republish
    end

    module ClassMethods
      attr_reader :on_message_return_callback

      def before_republish(*filters, &blk)
        set_callback(:republish, :before, *filters, &blk)
      end

      def around_republish(*filters, &blk)
        set_callback(:republish, :around, *filters, &blk)
      end

      def after_republish(*filters, &blk)
        set_callback(:republish, :after, *filters, &blk)
      end

      def on_message_return(method_or_proc)
        unless method_or_proc.is_a?(Proc) || method_or_proc.is_a?(Symbol)
          raise ArgumentError, "Method or Proc expected, #{method_or_proc.class} given"
        end

        @on_message_return_callback = method_or_proc
      end
    end

    attr_reader :queue_name, :queue_options

    def initialize(queue: nil, queue_options: {}, timeout_at_exit: 5, **options)
      super(**options)

      @queue_name = queue
      @queue_options = queue_options
      @returned_messages = ::Queue.new # ruby queue, not Bunny's one

      at_exit { wait_for_unrouted_messages_processing(timeout: timeout_at_exit) }
    end

    def publish(message, options = {})
      super(message, options.merge(mandatory: true))
    end

    def declare_republish_queue
      name = queue_name || message_options[:routing_key]

      ensure_can_create_queue!(name)

      channel.queue(name, queue_options)
    end

    def declare_republish_queue_binding(queue)
      routing_key = message_options[:routing_key] || queue_name

      queue.bind(exchange, routing_key: routing_key)
    end

    private

    attr_reader :returned_messages

    def ensure_connection!
      super

      return if @on_return_set

      case (callback = self.class.on_message_return_callback)
      when nil
        exchange.on_return { |*attrs| on_message_return(*attrs) }
      when Proc
        exchange.on_return { |*attrs| callback.call(*attrs) }
      when Symbol
        exchange.on_return { |*attrs| send(callback, *attrs) }
      end

      @on_return_set = true
    end

    # `on_return` is called within a frameset of amqp connection.
    # Any interaction within the same connection leads to error.
    # This is why we process the returned message in a separate thread.
    # https://github.com/ruby-amqp/bunny/blob/7fb05abf36637557f75a69790be78f9cc1cea807/lib/bunny/session.rb#L683
    def on_message_return(return_info, properties, message)
      message_options = properties.to_h.merge(routing_key: return_info.routing_key).compact

      if return_info.reply_text == 'NO_ROUTE'
        returned_messages << [message, message_options]

        Thread.new { process_returned_message }.tap do |thread|
          thread.abort_on_exception = false
          thread.report_on_exception = true
        end
      else
        # Do not raise error here!
        # The best we can do here is to log to STDERR
        warn 'BunnyPublisher::UnsupportedReplyText: '\
             'Broker has returned the message with reply_text other than NO_ROUTE '\
             "#{[return_info, properties, message]}"
      end
    end

    def process_returned_message
      @mutex.synchronize do
        @unrouted_message_processing = true
        @message, @message_options = returned_messages.pop

        ensure_connection!
        setup_queue_for_republish

        run_callbacks(:republish) do
          exchange.publish(message, message_options.merge(mandatory: true))
        end
      ensure
        @message = @message_options = nil
        @unrouted_message_processing = false
      end
    end

    def setup_queue_for_republish
      queue = declare_republish_queue

      # default exchange already has bindings with queues, but routing key is required
      if exchange.name == ''
        message_options[:routing_key] = queue.name
      else
        declare_republish_queue_binding(queue)
      end

      channel.deregister_queue(queue) # we are not going to work with this queue in this channel
    end

    # TODO: introduce more reliable way to wait for handling of unrouted messages at exit
    def wait_for_unrouted_messages_processing(timeout:)
      sleep(0.05) # gives exchange some time to receive retuned message

      return unless @unrouted_message_processing

      puts("Waiting up to #{timeout} seconds for unrouted messages handling")

      Timeout.timeout(timeout) { sleep 0.01 while @unrouted_message_processing }
    rescue Timeout::Error
      warn('Some unrouted messages are lost on process exit!')
    end

    def ensure_can_create_queue!(name)
      return if name.present?

      raise BunnyPublisher::CannotCreateQueue, message: message,
                                               message_options: message_options
    end
  end
end
