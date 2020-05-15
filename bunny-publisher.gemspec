# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bunny_publisher/version'

Gem::Specification.new do |spec|
  spec.name          = 'bunny-publisher'
  spec.version       = BunnyPublisher::VERSION
  spec.authors       = ['Rustam Sharshenov']
  spec.email         = ['rustam@sharshenov.com']

  spec.summary       = 'AMQP publisher for RabbitMQ based on Bunny'
  spec.description   = 'AMQP publisher for RabbitMQ based on Bunny'
  spec.homepage      = 'https://github.com/veeqo/bunny-publisher'
  spec.license       = 'MIT'

  if spec.respond_to?(:metadata)
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = spec.homepage
    spec.metadata['changelog_uri'] = 'https://github.com/veeqo/bunny-publisher/blob/master/CHANGELOG.md'
  end

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(spec|\.ci)/}) }
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'bunny', '~> 2.10'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rabbitmq_http_api_client', '~> 1.13'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
end
