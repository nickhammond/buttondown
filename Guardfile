# frozen_string_literal: true

guard :rubocop, all_on_start: false do
  watch(/.+\.rb$/)
end

guard :minitest, all_on_start: false do
  watch(%r{^test/(.*/)?([^/]+)_test\.rb$})
  watch(%r{^lib/(.*/)?([^/]+)\.rb$}) do |m|
    "test/#{m[1]}#{m[2]}_test.rb"
  end
  watch(%r{^test/test_helper\.rb$}) { "test" }
end
