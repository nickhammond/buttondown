# frozen_string_literal: true

require "test_helper"

class TestButtondown < Minitest::Test
  GEMSPEC = File.expand_path("../buttondown.gemspec", __dir__)
  LIB_FILES = Dir[File.expand_path("../lib/**/*.rb", __dir__)].freeze

  describe "the gem itself" do
    it "has a semantic version" do
      assert_match(/\A\d+\.\d+\.\d+/, Buttondown::VERSION)
    end

    it "declares no runtime dependencies" do
      assert_empty Gem::Specification.load(GEMSPEC).runtime_dependencies
    end

    it "never reaches for Rails or ActiveSupport" do
      refute_empty LIB_FILES

      LIB_FILES.each do |file|
        # Comments are allowed to mention Rails; code is not.
        code = File.readlines(file).reject { |line| line.strip.start_with?("#") }.join

        refute_match(
          /ActiveSupport|\bRails\b|\.blank\?|\.present\?/,
          code,
          "#{file} depends on Rails"
        )
      end
    end

    it "loads net/http but nothing from Rails or ActiveSupport" do
      refute_empty $LOADED_FEATURES.grep(%r{net/http})
      assert_empty $LOADED_FEATURES.grep(%r{active_support|activesupport|/rails})
    end
  end
end
