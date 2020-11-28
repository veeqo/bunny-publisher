# frozen_string_literal: true

describe BunnyPublisher::Mandatory, '#publish', :rabbitmq do
  subject { publish_message }

  let(:queue_name)      { 'baz' }
  let(:routing_key)     { 'baz' }
  let(:message)         { '{"foo":"bar"}' }
  let(:content_type)    { 'application/json' }
  let(:message_options) { { routing_key: routing_key, content_type: content_type } }

  let(:publisher_class) do
    Class.new(BunnyPublisher::Base).tap { |klass| klass.include(BunnyPublisher::Mandatory) }
  end

  after { publisher.stop }

  shared_examples 'no message returned' do
    it 'does not declare new exchange' do
      expect { publish_message }.not_to change { rabbitmq.list_exchanges.count }
    end

    it 'does not create new queue' do
      expect { publish_message }.not_to change { rabbitmq.list_queues.count }
    end

    it 'does not create new binding' do
      expect { publish_message }.not_to change { rabbitmq.list_queue_bindings(queue_name).count }
    end
  end

  context 'when publishing to the default exchange' do
    let(:publisher) { publisher_class.new }

    context 'when message is routed' do
      before do
        rabbitmq.declare_queue(routing_key, {})
      end

      include_examples 'no message returned'

      it 'publishes the message' do
        publish_message

        expect(rabbitmq.messages(routing_key).first['payload']).to eq message
      end
    end

    context 'when message is not routed' do
      shared_examples 'for message routed in default exchange' do
        context 'when message is routed' do
          before { rabbitmq.declare_queue(queue_name, {}) }

          it 'does not declare any exchange' do
            expect { publish_message }.not_to change { rabbitmq.list_exchanges.count }
          end

          it 'does not create any queue' do
            expect { publish_message }.not_to change { rabbitmq.list_queues.count }
          end

          it_behaves_like 'a message publisher' do
            let(:expected_exchange_name) { '' } # '' - is default exchange
            let(:expected_payload)       { message }
            let(:expected_properties)    { { 'content_type' => content_type } }
            let(:expected_routing_key)   { routing_key }
            let(:expected_queue_name)    { queue_name }
          end
        end
      end

      context 'when publisher has original declare_republish_queue method' do
        include_examples 'for message routed in default exchange'

        shared_examples 'for message republishing' do
          it 'does not declare any exchange' do
            expect { publish_message }.not_to change { rabbitmq.list_exchanges.count }
          end

          it 'creates a queue named with proper params' do
            expect { publish_message }.to change { rabbitmq.list_queues }.from([]).to([expected_queue])
          end

          it 'does not create an additional binding despite the default binding' do
            publish_message

            expected_bindings = [
              {
                'arguments' => {},
                'destination' => queue_name,
                'routing_key' => routing_key,
                'source' => ''
              }
            ]

            expect(rabbitmq.list_queue_bindings(queue_name)).to match_array expected_bindings
          end

          it 're-publishes the message' do
            publish_message

            expect(rabbitmq.messages('baz').first['payload']).to eq message
          end
        end

        context 'when publisher has no queue name' do
          context 'when publishing with routing_key' do
            let(:expected_queue) do
              {
                'name' => 'baz',
                'arguments' => {},
                'auto_delete' => false,
                'durable' => false,
                'exclusive' => false
              }
            end

            include_examples 'for message republishing'
          end

          context 'when publishing without routing_key' do
            subject(:publish_message) do
              publisher.publish(message)
              sleep 0.1 # unrouted messages are processed asynchronously
            end

            it 'prints error to STDERR' do
              expect { subject }.to output(/CannotCreateQueue/).to_stderr
            end
          end
        end

        context 'when publisher has queue name' do
          let(:publisher) { publisher_class.new queue: 'baz', queue_options: { durable: true } }

          let(:expected_queue) do
            {
              'name' => 'baz',
              'arguments' => {},
              'auto_delete' => false,
              'durable' => true,
              'exclusive' => false
            }
          end

          context 'when publishing with routing_key' do
            include_examples 'for message republishing'
          end

          context 'when publishing without routing_key' do
            subject(:publish_message) do
              publisher.publish(message)
              sleep 0.1 # unrouted messages are processed asynchronously
            end

            include_examples 'for message republishing'
          end
        end
      end

      context 'when publisher has declare_republish_queue overridden' do
        let(:publisher_class) do
          Class.new(BunnyPublisher::Base).tap do |klass|
            klass.include(BunnyPublisher::Mandatory)
            klass.class_eval <<-RUBY
              def declare_republish_queue
                channel.queue(message_options[:routing_key], durable: true, arguments: { 'x-something' => 'custom' })
              end
            RUBY
          end
        end

        include_examples 'for message routed in default exchange'

        context 'when message is not routed' do
          it 'does not declare any exchange' do
            expect { publish_message }.not_to change { rabbitmq.list_exchanges.count }
          end

          it 'creates proper queue' do
            expected_queues = [
              {
                'name' => queue_name,
                'arguments' => { 'x-something' => 'custom' },
                'auto_delete' => false,
                'durable' => true,
                'exclusive' => false
              }
            ]

            expect { publish_message }.to change { rabbitmq.list_queues }.from([]).to(expected_queues)
          end

          it 'does not create an additional binding despite the default binding' do
            publish_message

            expected_bindings = [
              {
                'arguments' => {},
                'destination' => queue_name,
                'routing_key' => routing_key,
                'source' => ''
              }
            ]

            expect(rabbitmq.list_queue_bindings(queue_name)).to match_array expected_bindings
          end

          it 're-publishes the message' do
            publish_message

            expect(rabbitmq.messages(queue_name).first['payload']).to eq message
          end
        end
      end
    end
  end

  context 'when publishing to a custom exchange' do
    let(:exchange_name) { 'custom' }
    let(:publisher) { publisher_class.new exchange: exchange_name }

    context 'when message is routed' do
      before do
        rabbitmq.declare_exchange(exchange_name, durable: false)
        rabbitmq.declare_queue(queue_name, {})
        rabbitmq.bind_queue(queue_name, exchange_name, routing_key)
      end

      include_examples 'no message returned'

      it_behaves_like 'a message publisher' do
        let(:expected_exchange_name) { exchange_name }
        let(:expected_payload)       { message }
        let(:expected_properties)    { { 'content_type' => content_type } }
        let(:expected_routing_key)   { routing_key }
        let(:expected_queue_name)    { queue_name }
      end
    end

    context 'when message is not routed' do
      context 'when publisher has no methods overriden' do
        shared_examples 'for message republishing' do
          it 'declares custom exchange with default params' do
            publish_message

            expected_exchange = {
              'name' => exchange_name,
              'arguments' => {},
              'auto_delete' => false,
              'durable' => false,
              'type' => 'direct'
            }

            expect(rabbitmq.list_exchanges).to include(expected_exchange)
          end

          it 'creates a queue with proper options' do
            expect { publish_message }.to change { rabbitmq.list_queues }.from([]).to([expected_queue])
          end

          it 'creates a binding by routing key' do
            publish_message

            expected_binding = {
              'arguments' => {},
              'destination' => expected_queue_name,
              'routing_key' => routing_key,
              'source' => exchange_name
            }

            expect(rabbitmq.list_queue_bindings(expected_queue_name)).to include(expected_binding)
          end

          it 're-publishes the message' do
            publish_message

            expect(rabbitmq.messages(expected_queue_name).first['payload']).to eq message
          end
        end

        context 'when publisher has no queue params' do
          context 'when publishing with routing_key' do
            let(:expected_queue_name) { 'baz' }

            let(:expected_queue) do
              {
                'name' => expected_queue_name,
                'arguments' => {},
                'auto_delete' => false,
                'durable' => false,
                'exclusive' => false
              }
            end

            include_examples 'for message republishing'
          end

          context 'when publishing without routing_key' do
            subject(:publish_message) do
              publisher.publish(message)
              sleep 0.1 # unrouted messages are processed asynchronously
            end

            it 'prints error to STDERR' do
              expect { subject }.to output(/CannotCreateQueue/).to_stderr
            end
          end
        end

        context 'when publisher has queue params' do
          let(:publisher) do
            publisher_class.new exchange: exchange_name,
                                queue: 'awesome',
                                queue_options: { durable: true }
          end

          let(:expected_queue_name) { 'awesome' }

          let(:expected_queue) do
            {
              'name' => expected_queue_name,
              'arguments' => {},
              'auto_delete' => false,
              'durable' => true,
              'exclusive' => false
            }
          end

          include_examples 'for message republishing'
        end
      end

      context 'when publisher has declare_republish_queue overridden' do
        let(:publisher_class) do
          Class.new(BunnyPublisher::Base).tap do |klass|
            klass.include(BunnyPublisher::Mandatory)
            klass.class_eval <<-RUBY
              def declare_republish_queue
                channel.queue(message_options[:routing_key], durable: true, arguments: { 'x-something' => 'custom' })
              end
            RUBY
          end
        end

        it 'declares custom exchange with default params' do
          publish_message

          expected_exchange = {
            'name' => exchange_name,
            'arguments' => {},
            'auto_delete' => false,
            'durable' => false,
            'type' => 'direct'
          }

          expect(rabbitmq.list_exchanges).to include(expected_exchange)
        end

        it 'creates proper queue' do
          expected_queues = [
            {
              'name' => queue_name,
              'arguments' => { 'x-something' => 'custom' },
              'auto_delete' => false,
              'durable' => true,
              'exclusive' => false
            }
          ]

          expect { publish_message }.to change { rabbitmq.list_queues }.from([]).to(expected_queues)
        end

        it 'creates a binding' do
          publish_message

          expected_binding = {
            'arguments' => {},
            'destination' => queue_name,
            'routing_key' => routing_key,
            'source' => exchange_name
          }

          expect(rabbitmq.list_queue_bindings(queue_name)).to include(expected_binding)
        end

        it 're-publishes the message' do
          publish_message

          expect(rabbitmq.messages(queue_name).first['payload']).to eq message
        end
      end

      context 'when publisher has declare_republish_queue_binding overridden' do
        let(:message_options) { { content_type: 'text/plain', headers: { 'document' => 'text' } } }

        let(:publisher) do
          publisher_class.new exchange: exchange_name,
                              exchange_options: { type: 'headers' }
        end

        let(:publisher_class) do
          Class.new(BunnyPublisher::Base).tap do |klass|
            klass.include(BunnyPublisher::Mandatory)
            klass.class_eval <<-RUBY
              def declare_republish_queue
                channel.queue('unrouted-docs', durable: true, arguments: { 'x-something' => 'custom' })
              end

              def declare_republish_queue_binding(queue)
                queue.bind(exchange, arguments: { 'document' => 'text' })
              end
            RUBY
          end
        end

        it 'declares custom exchange with preoper params' do
          publish_message

          expected_exchange = {
            'name' => exchange_name,
            'arguments' => {},
            'auto_delete' => false,
            'durable' => false,
            'type' => 'headers'
          }

          expect(rabbitmq.list_exchanges).to include(expected_exchange)
        end

        it 'creates proper queue' do
          expected_queues = [
            {
              'name' => 'unrouted-docs',
              'arguments' => { 'x-something' => 'custom' },
              'auto_delete' => false,
              'durable' => true,
              'exclusive' => false
            }
          ]

          expect { publish_message }.to change { rabbitmq.list_queues }.from([]).to(expected_queues)
        end

        it 'creates proper binding' do
          publish_message

          expected_binding = {
            'arguments' => { 'document' => 'text' },
            'routing_key' => '',
            'source' => exchange_name,
            'destination' => 'unrouted-docs'
          }

          expect(rabbitmq.list_queue_bindings('unrouted-docs')).to include(expected_binding)
        end

        it 're-publishes the message' do
          publish_message

          expect(rabbitmq.messages('unrouted-docs').first['payload']).to eq message
        end
      end
    end
  end

  describe 'connection state handling' do
    let(:publisher) do
      publisher_class.new connection: connection
    end

    context 'when connection is closed by broker' do
      before do
        allow(publisher).to receive(:setup_queue_for_republish).and_wrap_original do |original|
          unless @connection_was_closed_once
            rabbitmq.close_connections
            @connection_was_closed_once = true
          end

          original.call
        end
      end

      context 'when connection recovery is enabled (by default)' do
        let(:connection) { Bunny.new(ENV['RABBITMQ_URL'], heartbeat: 5, log_level: Logger::ERROR) }

        it 'waits for connection recovery & publishes the message' do
          expect(rabbitmq.list_connections).to eq []
          connection.start

          # rmq updates stats every 5 second so we have to wait a bit to get actual connections list via http API
          Timeout.timeout(5.01) { sleep 0.1 while rabbitmq.list_connections == [] }

          expect do
            publish_message
            Timeout.timeout(20) { sleep 0.1 until publisher.send(:connection_open?) }
            sleep(0.1)
          end.to change { messages_count }.by(1)
        end
      end

      context 'when connection recovery is disabled' do
        let(:connection) { Bunny.new(ENV['RABBITMQ_URL'], automatic_recovery: false, heartbeat: 5, log_level: Logger::ERROR) }

        before { allow(publisher).to receive(:sleep) }

        it 'does not wait for connection recovery & fails to publish the message' do
          expect(rabbitmq.list_connections).to eq []
          connection.start

          # rmq updates stats every 5 second so we have to wait a bit to get actual connections list via http API
          Timeout.timeout(5.01) { sleep 0.1 while rabbitmq.list_connections == [] }

          expect { publish_message && sleep(0.2) }.to not_change { messages_count }
                                                  .and output(/Bunny::ConnectionClosedError/).to_stderr

          expect(publisher).not_to have_received(:sleep)
        end
      end
    end

    context 'when connection is closed by client' do
      let(:connection) { Bunny.new(ENV['RABBITMQ_URL'], heartbeat: 5) }

      before do
        allow(publisher).to receive(:setup_queue_for_republish).and_wrap_original do |original|
          unless @connection_was_closed_once
            connection.close
            @connection_was_closed_once = true
          end

          original.call
        end
      end

      it 'restarts the connection & publishes the message' do
        expect(rabbitmq.list_connections).to eq []
        connection.start

        # rmq updates stats every 5 second so we have to wait a bit to get actual connections list via http API
        Timeout.timeout(5.01) { sleep 0.1 while rabbitmq.list_connections == [] }

        expect do
          publish_message
          Timeout.timeout(10) { sleep 0.1 until connection.connected? }
        end.to change { messages_count }.by(1)
      end
    end
  end

  context 'when broker retuns message with unsupported reply_text' do
    before { allow_any_instance_of(Bunny::ReturnInfo).to receive(:reply_text).and_return('GTFO') }

    let(:publisher) { publisher_class.new }

    it 'prints error to STDERR' do
      expect { subject }.to output(/UnsupportedReplyText/).to_stderr
    end
  end

  def publish_message
    publisher.publish(message, message_options)
    sleep 0.1 # unrouted messages are processed asynchronously
  end

  def messages_count
    rabbitmq.messages(queue_name, count: 999).count
  rescue Faraday::ResourceNotFound
    0
  end
end
