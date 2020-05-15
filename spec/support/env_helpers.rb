# frozen_string_literal: true

RSpec.configure do |config|
  # Tag that makes example run with patched ENV and ensures that ENV restored with previous values
  #
  # Usage:
  # it 'tests something related to ENV', with_env: { 'FOO' => 'bar' } do
  #   # test code
  # end
  config.around :each, :with_env do |ex|
    was = {}

    ex.metadata.fetch(:with_env).each do |key, value|
      was[key] = ENV[key]
      value.nil ? ENV.delete(key) : ENV[key] = value
    end

    ex.run

    was.each { |key, value| ENV[key] = value }
  end
end
