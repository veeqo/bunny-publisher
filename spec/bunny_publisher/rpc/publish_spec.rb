# frozen_string_literal: true

describe BunnyPublisher::RPC, '#publish', rpc: 'rpc_queue' do
  subject(:publish_message) { publisher.publish('message', routing_key: 'rpc_queue') }

  let(:publisher) { publisher_class.new }

  let(:publisher_class) do
    Class.new(BunnyPublisher::Base) do
      include BunnyPublisher::Mandatory # to be sure that message is not lost if rpc_server starts slowly
      include BunnyPublisher::RPC
    end
  end

  after { publisher.stop }

  it 'returns RPC result' do
    expect(publish_message).to eq('processed message')
  end
end
