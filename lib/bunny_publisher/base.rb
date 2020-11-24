# frozen_string_literal: true

module BunnyPublisher
  # Based on Publisher of Sneakers
  # https://github.com/jondot/sneakers/blob/ed620b642b447701be490666ee284cf7d60ccf22/lib/sneakers/publisher.rb
  class Base
    include Callbacks

    define_callbacks :after_publish, :before_publish, :around_publish

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

    def publish(message, options = {})
      @mutex.synchronize do
        ensure_connection!

        run_callback(:before_publish, message, options)
        result = run_callback(:around_publish, message, options) { exchange.publish(message, options) }
        run_callback(:after_publish, message, options)

        result
      end
    end

    def close
      connection&.close
    end

    alias stop close

    private

    def ensure_connection!
      @connection ||= build_connection

      connection.start if connection.status == :not_connected # Lazy connection initialization.

      wait_until_connection_ready(connection)

      @channel ||= connection.create_channel
      @exchange ||= build_exchange
    end

    def wait_until_connection_ready(conn)
      Timeout.timeout((conn.heartbeat || 60) * 2) do # 60 seconds is a default Bunny heartbeat
        loop do
          return if conn.status == :open && conn.transport.open?

          sleep 0.001
        end
      end
    rescue Timeout::Error
      # Connection recovery takes too long, let the next interaction fail with error then.
    end

    def build_connection
      Bunny.new(@options[:amqp] || ENV['RABBITMQ_URL'], @options)
    end

    def build_exchange
      return channel.default_exchange if @exchange_name.nil? || @exchange_name == ''

      channel.exchange(@exchange_name, @exchange_options)
    end
  end
end
