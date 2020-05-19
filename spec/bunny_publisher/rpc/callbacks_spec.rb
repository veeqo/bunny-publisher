# frozen_string_literal: true

describe BunnyPublisher::RPC, 'callbacks', rpc: 'rpc_queue' do
  subject(:publish_message) { publisher.publish(message, routing_key: 'rpc_queue') }

  let(:publisher) { publisher_class.new }
  let(:message)   { 'message' }

  let(:publisher_class) do
    Class.new(BunnyPublisher::Base) do
      include BunnyPublisher::Mandatory # to be sure that message is not lost if rpc_server starts slowly
      include BunnyPublisher::RPC

      before_publish :my_before_publish_callback
      after_publish :my_after_publish_callback
      around_publish :my_around_publish_callback
      before_rpc :my_before_rpc_callback
      around_rpc :my_around_rpc_callback
      after_rpc :my_after_rpc_callback

      def callbacks_history
        @callbacks_history ||= []
      end

      def my_before_publish_callback(_publisher, message, message_options)
        callbacks_history << ['before publish', message, message_options.dup]
      end

      def my_after_publish_callback(_publisher, message, message_options)
        callbacks_history << ['after publish', message, message_options.dup]
      end

      def my_around_publish_callback(_publisher, message, message_options)
        callbacks_history << ['around before publish', message, message_options.dup]
        yield
        callbacks_history << ['around after publish', message, message_options.dup]
      end

      def my_before_rpc_callback(_publisher, message, message_options, rpc_call_id)
        callbacks_history << ['before rpc', message, message_options.dup, rpc_call_id]
      end

      def my_around_rpc_callback(_publisher, message, message_options, rpc_call_id)
        callbacks_history << ['around before rpc', message, message_options.dup, rpc_call_id]
        yield
        callbacks_history << ['around after rpc', message, message_options.dup, rpc_call_id]
      end

      def my_after_rpc_callback(_publisher, message, message_options, rpc_call_id, rpc_response)
        callbacks_history << ['after rpc', message, message_options.dup, rpc_call_id, rpc_response]
      end
    end
  end

  after { publisher.stop }

  it 'runs callbacks in proper order' do
    expected_callbacks = [
      ['before rpc', 'message', { routing_key: 'rpc_queue' }, String],
      ['around before rpc', 'message', { routing_key: 'rpc_queue' }, String],
      ['before publish', 'message', { correlation_id: String, mandatory: true, reply_to: String, routing_key: 'rpc_queue' }],
      ['around before publish', 'message', { correlation_id: String, mandatory: true, reply_to: String, routing_key: 'rpc_queue' }],
      ['around after publish', 'message', { content_type: 'application/octet-stream', correlation_id: String, delivery_mode: 2, mandatory: true, priority: 0, reply_to: String }],
      ['after publish', 'message', { content_type: 'application/octet-stream', correlation_id: String, delivery_mode: 2, mandatory: true, priority: 0, reply_to: String }],
      ['around after rpc', 'message', { routing_key: 'rpc_queue' }, String],
      ['after rpc', 'message', { routing_key: 'rpc_queue' }, String, 'processed message']
    ]

    expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
  end
end
