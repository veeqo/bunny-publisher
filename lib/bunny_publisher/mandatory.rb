# frozen_string_literal: true

module BunnyPublisher
  # Enforces mandatory option for message publishing.
  # Catches returned message if they are not routed.
  # Creates queue/binding before re-publishing the same message again.
  # This publisher DUPLICATES the connection for re-publishing messages!
  module Mandatory
    def self.included(klass)
      klass.define_callbacks :on_message_return,
                             :after_republish,
                             :before_republish,
                             :around_republish
    end

    attr_reader :queue_name, :queue_options

    def initialize(republish_connection: nil, queue: nil, queue_options: {}, timeout_at_exit: 5, **options)
      super(**options)

      @queue_name = queue
      @queue_options = queue_options

      @republish_mutex = Mutex.new
      @republish_connection = republish_connection

      at_exit { wait_for_unrouted_messages_processing(timeout: timeout_at_exit) }
    end

    def publish(message, options = {})
      super(message, options.merge(mandatory: true))
    end

    def close
      republish_connection&.close

      super
    end

    alias stop close

    def declare_republish_queue(return_info, _properties, _message)
      republish_channel.queue(queue_name || return_info.routing_key, queue_options)
    end

    def declare_republish_queue_binding(queue, return_info, _properties, _message)
      queue.bind(republish_exchange, routing_key: return_info.routing_key)
    end

    private

    attr_reader :republish_connection

    def connect!
      super

      # `on_return` is called within a frameset of amqp connection.
      # Any interaction within the same connection leads to error. This is why we need extra connection.
      # https://github.com/ruby-amqp/bunny/blob/7fb05abf36637557f75a69790be78f9cc1cea807/lib/bunny/session.rb#L683
      if callback_for_event(:on_message_return)
        exchange.on_return { |*attrs| run_callback(:on_message_return, *attrs) }
      else
        exchange.on_return { |*attrs| on_message_return(*attrs) }
      end
    end

    def ensure_republish_connection!
      @republish_mutex.synchronize { connect_for_republish! unless connected_for_republish? }
    end

    def connected_for_republish?
      republish_connection&.connected? && republish_channel
    end

    def connect_for_republish!
      @republish_connection ||= build_republish_connection
      republish_connection.start

      republish_connection_variables[:republish_channel] ||= republish_connection.create_channel
      republish_connection_variables[:republish_exchange] ||= build_republish_exchange
    end

    def republish_connection_variables
      thread_variables[republish_connection] ||= {}
    end

    def republish_channel
      republish_connection_variables[:republish_channel]
    end

    def republish_exchange
      republish_connection_variables[:republish_exchange]
    end

    def build_republish_connection
      Bunny.new(connection.instance_variable_get(:'@opts')) # TODO: find more elegant way to "clone" connection
    end

    def build_republish_exchange
      return republish_channel.default_exchange if @exchange_name.nil? || @exchange_name == ''

      republish_channel.exchange(@exchange_name, @exchange_options)
    end

    def on_message_return(return_info, properties, message)
      @unrouted_message_processing = true

      ensure_message_is_unrouted!(return_info, properties, message)

      setup_queue_for_republish(return_info, properties, message)

      run_callback(:before_republish, return_info, properties, message)
      result = run_callback(:around_republish, return_info, properties, message) do
        republish_exchange.publish(message, properties.to_h.merge(routing_key: return_info.routing_key))
      end
      run_callback(:after_republish, return_info, properties, message)

      result
    ensure
      @unrouted_message_processing = false
    end

    def setup_queue_for_republish(return_info, properties, message)
      ensure_republish_connection!

      queue = declare_republish_queue(return_info, properties, message)

      # default exchange already has bindings with queues
      declare_republish_queue_binding(queue, return_info, properties, message) unless republish_exchange.name == ''

      republish_channel.deregister_queue(queue) # we are not going to work with this queue in this channel
    end

    def ensure_message_is_unrouted!(return_info, properties, message)
      return if return_info.reply_text == 'NO_ROUTE'

      raise BunnyPublisher::PublishError, message: message,
                                          return_info: return_info,
                                          properties: properties
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
  end
end
