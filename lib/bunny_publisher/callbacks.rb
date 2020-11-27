# frozen_string_literal: true

require 'active_support'
require 'active_support/callbacks'

module BunnyPublisher
  # Adds support for callbacks
  module Callbacks
    extend ActiveSupport::Concern
    include ActiveSupport::Callbacks

    included do
      define_callbacks :publish
    end

    module ClassMethods
      def before_publish(*filters, &blk)
        set_callback(:publish, :before, *filters, &blk)
      end

      def around_publish(*filters, &blk)
        set_callback(:publish, :around, *filters, &blk)
      end

      def after_publish(*filters, &blk)
        set_callback(:publish, :after, *filters, &blk)
      end
    end
  end
end
