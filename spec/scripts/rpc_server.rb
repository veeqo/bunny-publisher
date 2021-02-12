# frozen_string_literal: true

# Runs RPC server for a queue provided by first argument. Responds with the same message with "processed" word prepended
# Based on https://github.com/rabbitmq/rabbitmq-tutorials/blob/69519621003ce77a185d592898cf8baac589d014/ruby/rpc_server.rb

require 'bunny'

class RPCServer
  def initialize
    @connection = Bunny.new
    @connection.start
    @channel = @connection.create_channel
  end

  def start(queue_name)
    @queue = channel.queue(queue_name)
    @exchange = channel.default_exchange
    subscribe_to_queue
  end

  def stop
    channel.close
    connection.close
  end

  def loop_forever
    # This loop only exists to keep the main thread
    # alive. Many real world apps won't need this.
    loop { sleep 5 }
  end

  private

  attr_reader :channel, :exchange, :queue, :connection

  def subscribe_to_queue
    queue.subscribe do |_delivery_info, properties, payload|
      result = ['processed', payload].join(' ')

      exchange.publish(
        result.to_s,
        routing_key: properties.reply_to,
        correlation_id: properties.correlation_id
      )
    end
  end
end

begin
  server = RPCServer.new

  server.start(ARGV[0])
  server.loop_forever
rescue Interrupt
  server.stop
end
