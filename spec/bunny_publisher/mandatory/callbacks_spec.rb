# frozen_string_literal: true

describe BunnyPublisher::Mandatory, 'callbacks', :rabbitmq do
  subject(:publish_message) do
    publisher.publish(message, message_options)
    sleep 0.1 # unrouted messages are processed asynchronously
  end

  let(:publisher)       { publisher_class.new }
  let(:message)         { 'hello' }
  let(:message_options) { { routing_key: 'foobar', content_type: 'text/plain' } }

  after { publisher.stop }

  context 'when no on_message_return callback is set' do
    let(:publisher_class) do
      class MandatoryPublisherWithCallbacks < BunnyPublisher::Base
        include BunnyPublisher::Mandatory

        before_publish :my_before_publish_callback
        after_publish :my_after_publish_callback
        around_publish :my_around_publish_callback
        before_republish :my_before_republish_callback
        after_republish :my_after_republish_callback
        around_republish :my_around_republish_callback

        def callbacks_history
          @callbacks_history ||= []
        end

        def my_before_publish_callback
          callbacks_history << ['before publish', message, message_options]
        end

        def my_after_publish_callback
          callbacks_history << ['after publish', message, message_options]
        end

        def my_around_publish_callback
          callbacks_history << ['around before publish', message, message_options]
          yield
          callbacks_history << ['around after publish', message, message_options]
        end

        def my_before_republish_callback
          callbacks_history << ['before re-publish', message, message_options]
        end

        def my_after_republish_callback
          callbacks_history << ['after re-publish', message, message_options]
        end

        def my_around_republish_callback
          callbacks_history << ['around before re-publish', message, message_options]
          yield
          callbacks_history << ['around after re-publish', message, message_options]
        end
      end

      MandatoryPublisherWithCallbacks
    end

    context 'when message is routed' do
      before { rabbitmq.declare_queue('foobar', {}) }

      it 'runs publish callbacks only' do
        expected_callbacks = [
          ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
                                  .and change { rabbitmq.messages('foobar', count: 999).count }.by(1)
      end
    end

    context 'when message is not routed' do
      it 'runs all callbacks in proper order' do
        expected_callbacks = [
          ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['before re-publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0, routing_key: 'foobar' }],
          ['around before re-publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0, routing_key: 'foobar' }],
          ['around after re-publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0, routing_key: 'foobar' }],
          ['after re-publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0, routing_key: 'foobar' }]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
                                  .and change { rabbitmq.messages('foobar', count: 999).count rescue 0 }.by(1)
      end
    end
  end

  context 'when on_message_return callback is set' do
    let(:publisher_class) do
      class MandatoryPublisherWithOnReturnCallback < BunnyPublisher::Base
        include BunnyPublisher::Mandatory

        before_publish :my_before_publish_callback
        after_publish :my_after_publish_callback
        around_publish :my_around_publish_callback
        on_message_return :on_message_return_callback

        def callbacks_history
          @callbacks_history ||= []
        end

        def my_before_publish_callback
          callbacks_history << ['before publish', message, message_options]
        end

        def my_after_publish_callback
          callbacks_history << ['after publish', message, message_options]
        end

        def my_around_publish_callback
          callbacks_history << ['around before publish', message, message_options]
          yield
          callbacks_history << ['around after publish', message, message_options]
        end

        def on_message_return_callback(_return_info, _properties, message)
          callbacks_history << ['on message return', message]
        end
      end

      MandatoryPublisherWithOnReturnCallback
    end

    context 'when message is routed' do
      before { rabbitmq.declare_queue('foobar', {}) }

      it 'runs publish callbacks only' do
        expected_callbacks = [
          ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
                                  .and not_change { rabbitmq.list_queues.count }
      end
    end

    context 'when message is not routed' do
      it 'runs all callbacks in proper order' do
        expected_callbacks = [
          ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['after publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['on message return', message]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
                                  .and not_change { rabbitmq.list_queues.count }
      end
    end
  end
end
