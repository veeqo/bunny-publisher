# frozen_string_literal: true

describe BunnyPublisher::Base, 'callbacks', :rabbitmq do
  subject(:publish_message) { publisher.publish(message, message_options) }

  let(:publisher)       { publisher_class.new }
  let(:message)         { 'hello' }
  let(:message_options) { { routing_key: 'foobar', content_type: 'text/plain' } }

  after { publisher.stop }

  context 'when callbacks are declared with methods' do
    let(:publisher_class) do
      class MyAwesomeBasePublisher < BunnyPublisher::Base
        before_publish :my_before_publish_callback
        after_publish :my_after_publish_callback
        around_publish :my_around_publish_callback

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
      end

      MyAwesomeBasePublisher
    end

    it 'runs callbacks with proper arguments and in proper order' do
      expected_callbacks = [
        ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain' }],
        ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain' }],
        ['around after publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0 }],
        ['after publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0 }]
      ]

      expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
    end
  end

  context 'when callbacks are declared with procs' do
    let(:publisher_class) do
      class MyAwesomeBasePublisher < BunnyPublisher::Base
        before_publish lambda { |_publisher, message, message_options|
          callbacks_history << ['before publish', message, message_options.dup]
        }

        after_publish lambda { |_publisher, message, message_options|
          callbacks_history << ['after publish', message, message_options.dup]
        }

        around_publish lambda { |_publisher, message, message_options, &block|
          callbacks_history << ['around before publish', message, message_options.dup]
          block.call
          callbacks_history << ['around after publish', message, message_options.dup]
        }

        def self.callbacks_history
          @callbacks_history ||= []
        end
      end

      MyAwesomeBasePublisher
    end

    it 'runs callbacks with proper arguments and in proper order' do
      expected_callbacks = [
        ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain' }],
        ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain' }],
        ['around after publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0 }],
        ['after publish', message, { content_type: 'text/plain', delivery_mode: 2, priority: 0 }]
      ]

      expect { publish_message }.to change { publisher_class.callbacks_history }.from([]).to(expected_callbacks)
    end
  end
end
