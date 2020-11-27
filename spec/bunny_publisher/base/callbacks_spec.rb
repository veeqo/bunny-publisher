# frozen_string_literal: true

describe BunnyPublisher::Base, 'callbacks', :rabbitmq do
  subject(:publish_message) { publisher.publish(message, message_options) }

  let(:publisher)       { publisher_class.new }
  let(:message)         { 'hello' }
  let(:message_options) { { routing_key: 'foobar', content_type: 'text/plain' } }

  before { rabbitmq.declare_queue('foobar', {}) }

  after { publisher.stop }

  let(:publisher_class) do
    class MyAwesomeBasePublisher < BunnyPublisher::Base
      before_publish :my_before_publish_callback, :my_another_before_publish_callback
      after_publish :my_after_publish_callback
      after_publish :raise, if: -> { false } # test for filters
      around_publish :my_around_publish_callback

      def callbacks_history
        @callbacks_history ||= []
      end

      def my_before_publish_callback
        callbacks_history << ['before publish', message, message_options]
      end

      def my_another_before_publish_callback
        callbacks_history << ['another before publish', message, message_options]
      end

      def my_after_publish_callback
        callbacks_history << ['after publish', message, message_options]
      end

      def my_around_publish_callback
        callbacks_history << ['around before publish', message, message_options]
        yield
        callbacks_history << ['around after publish', message, message_options]
      end
    end

    MyAwesomeBasePublisher
  end

  it 'runs callbacks with proper arguments and in proper order' do
    expected_callbacks = [
      ['before publish', message, { routing_key: 'foobar', content_type: 'text/plain' }],
      ['another before publish', message, { content_type: 'text/plain', routing_key: 'foobar' }],
      ['around before publish', message, { routing_key: 'foobar', content_type: 'text/plain' }],
      ['around after publish', message, { routing_key: 'foobar', content_type: 'text/plain' }],
      ['after publish', message, { routing_key: 'foobar', content_type: 'text/plain' }]
    ]

    expect { publish_message }.to change { publisher.callbacks_history }.from([]).to(expected_callbacks)
                              .and change { rabbitmq.messages('foobar', count: 999).count }.by(1)
  end
end
