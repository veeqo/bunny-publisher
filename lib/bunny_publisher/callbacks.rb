# frozen_string_literal: true

module BunnyPublisher
  # Adds support for callbacks (one per event!)
  module Callbacks
    def self.included(klass)
      klass.extend ClassMethods
    end

    module ClassMethods
      def define_callbacks(*events)
        events.each do |event|
          singleton_class.define_method(event) do |method_or_proc|
            callbacks[event] = method_or_proc
          end
        end
      end

      def callbacks
        @callbacks ||= {}
      end
    end

    private

    def run_callback(event, *args, &block)
      case (callback = callback_for_event(event))
      when nil
        yield if block_given?
      when Symbol
        send(callback, self, *args, &block)
      when Proc
        callback.call(self, *args, &block)
      end
    end

    def callback_for_event(event)
      self.class.callbacks[event]
    end
  end
end
