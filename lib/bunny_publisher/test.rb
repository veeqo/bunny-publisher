# frozen_string_literal: true

module BunnyPublisher
  # Test module prevents real connections to be made and replaces exchange with array-based TestExchange
  module Test
    class TestExchange < Array
      def publish(message, options = {})
        self << [message, options]
        true
      end

      # in case if used with Mandatory module included
      def on_return(&block); end
    end

    def exchange
      @exchange ||= TestExchange.new
    end

    alias messages exchange

    def flush!
      exchange.clear
    end

    alias close flush!
    alias stop flush!

    private

    def ensure_connection!; end
  end
end
