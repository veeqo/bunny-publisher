# frozen_string_literal: true

require 'bundler/setup'
require 'pry-byebug'
require 'bunny/publisher'

ENV['RABBITMQ_URL'] ||= 'amqp://guest:guest@localhost:5672/bunny_publisher'

Dir['./spec/support/**/*.rb'].sort.each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.expect_with :rspec do |c|
    c.max_formatted_output_length = nil # Do not truncate 'expected'/'got' data
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
