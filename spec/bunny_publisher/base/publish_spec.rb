# frozen_string_literal: true

describe BunnyPublisher::Base, '#publish', :rabbitmq do
  subject(:publish_message) { publisher.publish(message, message_options) }

  let(:queue_name)      { 'baz' }
  let(:message)         { '{"foo":"bar"}' }
  let(:content_type)    { 'application/json' }
  let(:message_options) { { routing_key: queue_name, content_type: content_type } }

  after { publisher.stop }

  context 'when publisher is initialized with no options' do
    let(:publisher) { described_class.new }

    it 'does not declare any exchange' do
      expect { publish_message }.not_to change { rabbitmq.list_exchanges.count }
    end

    it 'does not create any queue' do
      expect { publish_message }.not_to change { rabbitmq.list_queues.count }
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

        expect { publish_message }.not_to change { rabbitmq.list_bindings_by_source(exchange_name).count }
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

        expect { publish_message }.not_to change { rabbitmq.list_bindings_by_source(exchange_name).count }
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
end
