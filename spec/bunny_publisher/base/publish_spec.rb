# frozen_string_literal: true

describe BunnyPublisher::Base, '#publish', :rabbitmq do
  subject { publish_message }

  let(:queue_name)      { 'baz' }
  let(:message)         { '{"foo":"bar"}' }
  let(:content_type)    { 'application/json' }
  let(:message_options) { { routing_key: queue_name, content_type: content_type } }

  after { publisher.stop }

  context 'when publisher is initialized with no options' do
    let(:publisher) { described_class.new }

    it 'does not declare any exchange' do
      expect { subject }.not_to change { rabbitmq.list_exchanges.count }
    end

    it 'does not create any queue' do
      expect { subject }.not_to change { rabbitmq.list_queues.count }
    end

    it_behaves_like 'a message publisher' do
      before { rabbitmq.declare_queue(queue_name, {}) }

      let(:expected_exchange_name) { '' } # '' - is default exchange
      let(:expected_payload)       { message }
      let(:expected_properties)    { { 'content_type' => content_type } }
      let(:expected_routing_key)   { queue_name }
      let(:expected_queue_name)    { queue_name }
    end
  end

  context 'when publisher is initialized with custom exchange name' do
    let(:exchange_name) { 'custom' }

    context 'when no exchange options given' do
      let(:publisher) { described_class.new exchange: exchange_name }

      it_behaves_like 'an exchange definer' do
        let(:expected_exchange_name) { exchange_name }
        let(:expected_exchange_type) { 'direct' } # direct is default type
      end

      it 'does not create any binding' do
        rabbitmq.declare_exchange(exchange_name, type: 'direct', durable: false)

        expect { subject }.not_to change { rabbitmq.list_bindings_by_source(exchange_name).count }
      end

      it_behaves_like 'a message publisher' do
        before do
          rabbitmq.declare_queue(queue_name, {})
          rabbitmq.declare_exchange(exchange_name, type: 'direct', durable: false)
          rabbitmq.bind_queue(queue_name, exchange_name, queue_name)
        end

        let(:expected_exchange_name) { exchange_name }
        let(:expected_payload)       { message }
        let(:expected_properties)    { { 'content_type' => content_type } }
        let(:expected_routing_key)   { queue_name }
        let(:expected_queue_name)    { queue_name }
      end
    end

    context 'when exchange options are given' do
      let(:publisher) { described_class.new exchange: exchange_name, exchange_options: { type: :fanout } }

      it_behaves_like 'an exchange definer' do
        let(:expected_exchange_name) { exchange_name }
        let(:expected_exchange_type) { 'fanout' }
      end

      it 'does not create any binding' do
        rabbitmq.declare_exchange(exchange_name, type: 'fanout', durable: false)

        expect { subject }.not_to change { rabbitmq.list_bindings_by_source(exchange_name).count }
      end

      it_behaves_like 'a message publisher' do
        before do
          rabbitmq.declare_queue(queue_name, {})
          rabbitmq.declare_exchange(exchange_name, type: 'fanout', durable: false)
          rabbitmq.bind_queue(queue_name, exchange_name, nil)
        end

        let(:expected_exchange_name) { exchange_name }
        let(:expected_payload)       { message }
        let(:expected_properties)    { { 'content_type' => content_type } }
        let(:expected_routing_key)   { queue_name }
        let(:expected_queue_name)    { queue_name }
      end
    end
  end

  describe 'connection state handling' do
    let(:publisher) { described_class.new connection: connection }
    let(:connection) { Bunny.new }

    before { rabbitmq.declare_queue(queue_name, {}) }

    context 'when connection is not started' do
      it 'starts the connection and publishes the message' do
        expect { publish_message }.to change { connection.status }.from(:not_connected).to(:open)
                                  .and change { messages_count }.by(1)
      end
    end

    context 'when connection is started in advance' do
      before do
        connection.start
        allow(publisher.connection).to receive(:start)
      end

      it 'does not try to start the connection again and publishes the message' do
        expect { publish_message }.to change { messages_count }.by(1)
        expect(publisher.connection).not_to have_received(:start)
      end
    end

    context 'when connection is closed by broker' do
      context 'when connection recovery is enabled (by default)' do
        let(:connection) { Bunny.new(ENV['RABBITMQ_URL'], heartbeat: 5, log_level: Logger::ERROR) }

        it 'waits for connection recovery & publishes the message' do
          expect(rabbitmq.list_connections).to eq []

          expect { publish_message }.to change { publisher.connection.status }.from(:not_connected).to(:open)
                                    .and change { messages_count }.by(1)

          wait_for_connections_list

          expect { rabbitmq.close_connections && sleep(0.1) }.to change { connection.status }.from(:open).to(:disconnected)

          expect { publish_message }.to change { publisher.connection.status }.from(:disconnected).to(:open)
                                    .and change { messages_count }.by(1)
        end
      end

      context 'when connection recovery is disabled' do
        let(:connection) { Bunny.new(ENV['RABBITMQ_URL'], automatic_recovery: false, heartbeat: 5, log_level: Logger::ERROR) }

        before { allow(publisher).to receive(:sleep) }

        it 'does not wait for connection recovery & fails to publish the message' do
          expect(rabbitmq.list_connections).to eq []

          expect { publish_message }.to change { publisher.connection.status }.from(:not_connected).to(:open)
                                    .and change { messages_count }.by(1)

          wait_for_connections_list

          expect { rabbitmq.close_connections && sleep(0.1) }.to change { connection.status }.from(:open).to(:disconnected)

          expect { publish_message }.to not_change { publisher.connection.status }.from(:disconnected)
                                    .and raise_error(Bunny::ConnectionClosedError)

          expect(publisher).not_to have_received(:sleep)
        end
      end
    end

    context 'when connection is closed by client' do
      it 'restarts the connection & publishes the message' do
        expect { publish_message }.to change { publisher.connection.status }.from(:not_connected).to(:open)
                                  .and change { messages_count }.by(1)

        connection.close

        expect { publish_message }.to change { publisher.connection.status }.from(:closed).to(:open)
                                  .and change { messages_count }.by(1)
      end
    end
  end

  def publish_message
    publisher.publish(message, message_options)
  end

  def messages_count
    rabbitmq.messages(queue_name, count: 999).count
  end

  def wait_for_connections_list
    # rmq updates stats every 5 second so we have to wait a bit to get actual connections list via http API
    Timeout.timeout(6) { sleep 0.1 while rabbitmq.list_connections == [] }
  end
end
