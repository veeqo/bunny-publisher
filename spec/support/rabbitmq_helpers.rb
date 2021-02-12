# frozen_string_literal: true

require 'rabbitmq/http/client'

module RabbitmqHelpers
  class HttpApi
    attr_reader :client, :vhost

    def initialize(amqp:, port: 15_672, scheme: 'http')
      uri = URI(amqp)
      @vhost = uri.path[%r{/([^/]+)}, 1]

      raise ArgumentError, 'Default vhost is not supported for tests' if vhost.nil?

      uri.scheme = scheme
      uri.port = port
      uri.path = '/'

      @client = RabbitMQ::HTTP::Client.new(uri.to_s)
    end

    def reset_vhost
      delete_vhost
      create_vhost
    end

    def list_queues(columns: %w[name passive durable exclusive auto_delete arguments], **query)
      client.list_queues(vhost, query.merge(columns: columns.join(',')))
    end

    def list_queue_bindings(queue, columns: %w[arguments destination routing_key source], **query)
      client.list_queue_bindings(vhost, queue, query.merge(columns: columns.join(',')))
    end

    def list_exchanges(columns: %w[name arguments auto_delete durable type], **query)
      client.list_exchanges(vhost, query.merge(columns: columns.join(',')))
    end

    def messages(queue, ackmode: 'ack_requeue_true', count: 1, encoding: 'auto')
      client.get_messages vhost,
                          queue,
                          ackmode: ackmode,
                          count: count,
                          encoding: encoding
    end

    def delete_vhost
      client.delete_vhost(vhost)
    rescue Faraday::ResourceNotFound
      # it is ok
    end

    def close_connections
      client.list_connections.each do |conn|
        client.close_connection(conn.fetch('name'))
      end
    end

    def method_missing(method_name, *args)
      if client.respond_to?(method_name)
        if %i[list_connections list_channels].include?(method_name)
          client.send(method_name, *args)
        else
          client.send(method_name, vhost, *args)
        end
      else
        super
      end
    end

    def respond_to_missing?(method_name, *args)
      client.respond_to?(method_name) || super
    end
  end

  def rabbitmq
    @rabbitmq ||= HttpApi.new(amqp: ENV.fetch('RABBITMQ_URL'))
  end
end

RSpec.configure do |config|
  config.include RabbitmqHelpers, :rabbitmq, :rpc
  config.before(:each, :rabbitmq) { rabbitmq.reset_vhost }

  config.before(:each, :rpc) { rabbitmq.reset_vhost }
  config.around(:each, :rpc) do |example|
    script = File.expand_path('../scripts/rpc_server.rb', __dir__)
    queue = example.metadata.fetch(:rpc)

    pid = Process.spawn(['ruby', script, queue].join(' '))

    example.run
  ensure
    Process.kill('TERM', pid)
  end
end
