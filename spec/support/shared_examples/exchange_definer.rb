# frozen_string_literal: true

shared_examples 'an exchange definer' do
  it 'declares an exchange' do
    expect { publish_message }.to change { rabbitmq.list_exchanges.count }.by(1)
  end

  describe 'created exchange' do
    subject(:exchange) do
      publish_message
      rabbitmq.exchange_info(expected_exchange_name)
    end

    it 'has proper params' do
      expect(exchange['type']).to eq expected_exchange_type
    end
  end
end
