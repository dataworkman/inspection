ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Rate-limit counters live in the cache; start every test from zero.
    setup { Rails.cache.clear }

    # Add more helper methods to be used by all tests here...
  end
end
