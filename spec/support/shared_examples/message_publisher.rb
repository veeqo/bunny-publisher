# frozen_string_literal: true

shared_examples 'a message publisher' do
  it 'publishes message to a proper exchange' do
    expected_message = {
      'exchange' => expected_exchange_name,
      'message_count' => 0,
      'payload' => expected_payload,
      'payload_bytes' => Integer,
      'payload_encoding' => 'string',
      'properties' => expected_properties.merge('delivery_mode' => 2, 'priority' => 0),
      'redelivered' => false,
      'routing_key' => expected_routing_key
    }

    expect { subject }.to change { rabbitmq.messages(expected_queue_name) }.from([]).to([expected_message])
  end
end
