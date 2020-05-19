# frozen_string_literal: true

module BunnyPublisher
  # based on https://github.com/rabbitmq/rabbitmq-tutorials/blob/69519621003ce77a185d592898cf8baac589d014/ruby/rpc_client.rb
  module RPC
    def self.included(klass)
      klass.define_callbacks :before_rpc,
                             :around_rpc,
                             :after_rpc
    end

    def initialize(*)
      require 'securerandom'

      super

      @rpc_lock = Mutex.new
      @rpc_condition = ConditionVariable.new
    end

    def publish(message, options = {})
      rpc_lock.synchronize do
        setup_reply_queue! unless reply_queue
        set_rpc_call_id!

        run_callback(:before_rpc, message, options, rpc_call_id)
      end

      run_callback(:around_rpc, message, options, rpc_call_id) do
        super message, options.merge(correlation_id: rpc_call_id, reply_to: reply_queue.name)

        rpc_lock.synchronize { rpc_condition.wait(rpc_lock) }
      end

      run_callback(:after_rpc, message, options, rpc_call_id, rpc_response)

      rpc_response
    end

    protected

    attr_reader :rpc_lock, :rpc_call_id, :rpc_condition
    attr_accessor :rpc_response

    private

    attr_reader :reply_queue

    def set_rpc_call_id!
      @rpc_call_id = SecureRandom.uuid
    end

    def setup_reply_queue!
      ensure_connection!

      @reply_queue = channel.queue('', exclusive: true)

      that = self
      reply_queue.subscribe do |_delivery_info, properties, payload|
        if properties[:correlation_id] == that.rpc_call_id
          that.rpc_response = payload

          # sends the signal to continue the execution of #call
          that.rpc_lock.synchronize { that.rpc_condition.signal }
        end
      end
    end
  end
end
