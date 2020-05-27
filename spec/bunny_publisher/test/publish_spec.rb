# frozen_string_literal: true

describe BunnyPublisher::Test, '#publish' do
  subject(:publish_message) { publisher.publish(message, message_options) }

  let(:publisher)       { publisher_class.new }
  let(:message)         { '{"foo":"bar"}' }
  let(:message_options) { { routing_key: 'baz', content_type: 'application/json' } }

  before { allow(Bunny).to receive(:new) }

  shared_examples 'a test publisher' do
    it 'does not initialize new connection' do
      publish_message

      expect(Bunny).not_to have_received(:new)
    end

    it 'captures published messages' do
      expect { publish_message }.to change(publisher, :messages).from([]).to([[message, expected_message_options]])
    end
  end

  context 'when no other modules are included' do
    let(:publisher_class) do
      Class.new(BunnyPublisher::Base) do
        include BunnyPublisher::Test
      end
    end

    it_behaves_like 'a test publisher' do
      let(:expected_message_options) { message_options }
    end
  end

  context 'when Mandatory module is included' do
    let(:publisher_class) do
      Class.new(BunnyPublisher::Base) do
        include BunnyPublisher::Mandatory
        include BunnyPublisher::Test
      end
    end

    it_behaves_like 'a test publisher' do
      let(:expected_message_options) { message_options.merge(mandatory: true) }
    end
  end

  context 'when callbacks are defined' do
    let(:publisher_class) do
      Class.new(BunnyPublisher::Base) do
        include BunnyPublisher::Test
        after_publish :after_publish

        attr_reader :callbacks_data

        def initialize(options = {})
          super
          @callbacks_data = []
        end

        def after_publish(*data)
          @callbacks_data << data
        end
      end
    end

    it_behaves_like 'a test publisher' do
      let(:expected_message_options) { message_options }
    end

    it 'fires callbacks' do
      expect { publish_message }.to change(publisher, :callbacks_data).from([])
    end
  end
end
