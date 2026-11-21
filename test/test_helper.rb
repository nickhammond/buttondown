# frozen_string_literal: true

require "simplecov"
require "simplecov-lcov"

SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
SimpleCov.formatter = SimpleCov::Formatter::LcovFormatter
SimpleCov.start do
  skip "/test/"
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "buttondown"

require "minitest/autorun"
require "mocha/minitest"
require "minitest/reporters"
require "webmock/minitest"

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]
