# frozen_string_literal: true

require 'bunny'
require 'bunny_publisher/version'
require 'bunny_publisher/callbacks'
require 'bunny_publisher/errors'
require 'bunny_publisher/base'
require 'bunny_publisher/mandatory'
require 'bunny_publisher/test'

module BunnyPublisher
  class << self
    def publish(message, options = {})
      publisher.publish(message, options)
    end

    def publisher
      @publisher ||= Base.new
    end

    def configure
      require 'ostruct'

      config = OpenStruct.new(mandatory: false, test: false)

      yield(config)

      klass = Class.new(Base) do
        include ::BunnyPublisher::Mandatory if config.delete_field(:mandatory)
        include ::BunnyPublisher::Test      if config.delete_field(:test)
      end

      @publisher = klass.new(config.to_h)
    end

    def method_missing(method_name, *args)
      if publisher.respond_to?(method_name)
        publisher.send(method_name, *args)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      publisher.respond_to?(method_name) || super
    end
  end
end
