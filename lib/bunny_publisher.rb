# frozen_string_literal: true

require 'bunny'
require 'bunny_publisher/version'
require 'bunny_publisher/callbacks'
require 'bunny_publisher/errors'
require 'bunny_publisher/base'
require 'bunny_publisher/mandatory'

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

      config = OpenStruct.new({})

      yield(config)

      klass = Class.new(Base).tap { |k| k.include(::BunnyPublisher::Mandatory) if config.delete_field(:mandatory) }

      @publisher = klass.new(config.to_h)
    end
  end
end
