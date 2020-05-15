# frozen_string_literal: true

describe BunnyPublisher::Mandatory, '#ensure_message_is_unrouted!' do
  subject { publisher.send(:ensure_message_is_unrouted!, return_info, double, double) }

  let(:publisher) { publisher_class.new }
  let(:return_info) { double }

  let(:publisher_class) do
    Class.new(BunnyPublisher::Base).tap { |klass| klass.include(BunnyPublisher::Mandatory) }
  end

  context 'when return_info reply_tex is not NO_ROUTE' do
    before { allow(return_info).to receive(:reply_text).and_return('SOMETHING_ELSE') }

    it 'raises BunnyPublisher::PublishError' do
      expect { subject }.to raise_error(BunnyPublisher::PublishError)
    end
  end

  context 'when return_info reply_tex is NO_ROUTE' do
    before { allow(return_info).to receive(:reply_text).and_return('NO_ROUTE') }

    it 'does not raise errors' do
      expect { subject }.not_to raise_error
    end
  end
end
