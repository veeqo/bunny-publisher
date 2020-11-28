# frozen_string_literal: true

module BunnyPublisher
  # Based on Publisher of Sneakers
  # https://github.com/jondot/sneakers/blob/ed620b642b447701be490666ee284cf7d60ccf22/lib/sneakers/publisher.rb
  class Base
    include Callbacks

    # A list of errors that can be fixed by a connection recovery
    RETRIABLE_ERRORS = [
      Bunny::ConnectionClosedError,
      Bunny::NetworkFailure,
      Bunny::ConnectionLevelException,
      Timeout::Error # can be raised by Bunny::Channel#with_continuation_timeout
    ].freeze

    attr_reader :connection, :channel, :exchange

    def initialize(publish_connection: nil, connection: nil, exchange: nil, exchange_options: {}, **options)
      @mutex = Mutex.new

      @exchange_name = exchange
      @exchange_options = exchange_options
      @options = options

      # Arguments are compatible with Sneakers::CONFIG and if connection given publisher will use it.
      # But using of same connection for publishing & consumers could cause problems.
      # https://www.cloudamqp.com/blog/2017-12-29-part1-rabbitmq-best-practice.html#separate-connections-for-publisher-and-consumer
      # Therefore, publish_connection allows to explicitly make publishers use different connection
      @connection = publish_connection || connection
    end

    def publish(message, message_options = {})
      @mutex.synchronize do
        @message = message
        @message_options = message_options

        run_callbacks(:publish) do
          with_errors_handling do
            ensure_connection!
            exchange.publish(message, message_options.dup) # Bunny modifies message options
          end
        end
      ensure
        @message = @message_options = nil
      end
    end

    def close
      connection&.close
    end

    alias stop close

    private

    attr_reader :message, :message_options

    delegate :logger, to: :connection

    def ensure_connection!
      @connection ||= build_connection

      connection.start if should_start_connection?

      wait_until_connection_ready

      @channel ||= connection.create_channel
      @exchange ||= build_exchange
    end

    def reset_exchange!
      ensure_connection!
      @channel = connection.create_channel
      @exchange = build_exchange
    end

    def wait_until_connection_ready
      Timeout.timeout(recovery_timeout * 2) do
        loop do
          return if connection_open? || !connection.automatically_recover?

          sleep 0.01
        end
      end
    rescue Timeout::Error
      # Connection recovery takes too long, let the next interaction fail with error then.
    end

    def should_start_connection?
      connection.status == :not_connected || # Lazy connection initialization
        connection.closed?
    end

    def connection_can_recover?
      connection.automatically_recover? && connection.should_retry_recovery?
    end

    def connection_open?
      # Do not trust Bunny::Session#open? - it uses :connected & :connecting statuses as "open",
      # while connection is not actually ready to work.
      connection.instance_variable_get(:@status_mutex).synchronize do
        connection.status == :open && connection.transport.open?
      end
    end

    def recovery_timeout
      # 60 seconds is a default heartbeat timeout https://www.rabbitmq.com/heartbeats.html#heartbeats-timeout
      # Recommended timeout is 5-20 https://www.rabbitmq.com/heartbeats.html#false-positives
      heartbeat_timeout = [
        (connection.respond_to?(:heartbeat_timeout) ? connection.heartbeat_timeout : connection.heartbeat) || 60,
        5
      ].max

      # Using x2 of heartbeat timeout to get Bunny chance to detect connection failure & try to recover it
      heartbeat_timeout * 2
    end

    def build_connection
      Bunny.new(@options[:amqp] || ENV['RABBITMQ_URL'], @options)
    end

    def build_exchange
      return channel.default_exchange if @exchange_name.nil? || @exchange_name == ''

      channel.exchange(@exchange_name, @exchange_options)
    end

    def with_errors_handling
      yield
    rescue Bunny::ChannelAlreadyClosed
      reset_exchange!
      retry
    rescue *RETRIABLE_ERRORS => e
      raise unless connection_can_recover?

      logger.warn { e.inspect }
      retry
    end
  end
end
