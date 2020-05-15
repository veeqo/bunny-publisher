# frozen_string_literal: true

describe BunnyPublisher, '.configure' do
  subject(:configure) do
    described_class.configure do |c|
      c.mandatory = true
      c.connection = connection
    end
  end

  let(:connection) { double }

  it 'defines new publisher' do
    expect { configure }.to change { described_class.publisher }
  end

  describe 'configured publisher' do
    subject(:publisher) do
      configure
      described_class.publisher
    end

    it 'has modules applied' do
      expect(publisher.class.ancestors).to include(BunnyPublisher::Mandatory)
    end

    it 'has config applied' do
      expect(publisher.connection).to eql connection
    end
  end
end
