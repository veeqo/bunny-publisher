# frozen_string_literal: true

describe BunnyPublisher::Test, '#flush!' do
  subject(:flush!) { publisher.flush! }

  let(:publisher) { publisher_class.new }
  let(:publisher_class) do
    Class.new(BunnyPublisher::Base) do
      include BunnyPublisher::Test
    end
  end

  before { publisher.publish 'message', with: 'options' }

  it 'flushes #messages' do
    expect { flush! }.to change(publisher, :messages).from([['message', { with: 'options' }]]).to([])
  end
end
