# frozen_string_literal: true

describe BunnyPublisher::Base, :rabbitmq do
  after { publisher.stop }

  context 'when initialized with bunny connection' do
    let(:publisher) { described_class.new connection: connection }
    let(:connection) { Bunny.new.tap(&:start) }

    before { connection.create_channel } # imitation of other activity (like consumer)

    it 'reuses given connection' do
      expect { publish_something }.not_to change { publisher.connection }.from(connection)
    end

    it 'creates a new channel and reuses it later', :aggregate_failures do
      expect { publish_something }.to change { channels_count }.by(1)

      expect { 3.times { publish_something } }.not_to change { channels_count }
    end

    def channels_count
      connection.instance_variable_get(:'@channels').size
    end
  end

  context 'when initialized without bunny connection' do
    let(:publisher) { described_class.new heartbeat: 42 }

    it 'initializes a new connection and reuses it later', :aggregate_failures do
      expect { publish_something }.to change { publisher.connection }.from(nil)

      expect { 3.times { publish_something } }.not_to change { rabbitmq.list_connections.count }
    end

    it 'creates a new channel and reuses it later', :aggregate_failures do
      publish_something

      expect { 3.times { publish_something } }.not_to change { channels_count }
    end

    def channels_count
      publisher.connection.instance_variable_get(:'@channels').size
    end

    describe 'created connection' do
      subject(:connection) { publisher.connection }

      before { publish_something }

      it 'is initialized with given options' do
        expect(connection.heartbeat).to eq 42
      end
    end
  end

  def publish_something
    publisher.publish('something')
  end
end
