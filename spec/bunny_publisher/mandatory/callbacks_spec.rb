# frozen_string_literal: true

describe BunnyPublisher::Mandatory, 'callbacks', :rabbitmq do
  subject(:publish_message) do
    publisher.publish(message, message_options.dup)
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
        around_republish :my_around_republish_callback
        after_republish :my_after_republish_callback

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

        def my_before_republish_callback(_publisher, _return_info, _properties, message)
          callbacks_history << ['before re-publish', message]
        end

        def my_after_republish_callback(_publisher, _return_info, _properties, message)
          callbacks_history << ['after re-publish', message]
        end

        def my_around_republish_callback(_publisher, _return_info, _properties, message)
          callbacks_history << ['around before re-publish', message]
          yield
          callbacks_history << ['around after re-publish', message]
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
          ['around after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }],
          ['after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
      end
    end

    context 'when message is not routed' do
      it 'runs all callbacks in proper order' do
        expected_callbacks = [
          ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }],
          ['after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }],
          ['before re-publish', message],
          ['around before re-publish', message],
          ['around after re-publish', message],
          ['after re-publish', message]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
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

        def on_message_return_callback(_publisher, _return_info, _properties, message)
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
          ['around after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }],
          ['after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
      end
    end

    context 'when message is not routed' do
      it 'runs all callbacks in proper order' do
        expected_callbacks = [
          ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain', mandatory: true }],
          ['around after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }],
          ['after publish', message, { content_type: 'text/plain', mandatory: true, delivery_mode: 2, priority: 0 }],
          ['on message return', message]
        ]

        expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
      end
    end
  end
end
