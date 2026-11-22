# frozen_string_literal: true

require_relative "lib/buttondown/version"

Gem::Specification.new do |spec|
  spec.name = "buttondown"
  spec.version = Buttondown::VERSION
  spec.authors = ["Nick Hammond"]
  spec.email = ["nick@shipyrd.io"]

  spec.summary = "Ruby client for the Buttondown newsletter API"
  spec.description = "A Ruby client for the Buttondown newsletter API."
  spec.homepage = "https://github.com/nickhammond/buttondown"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nickhammond/buttondown"
  spec.metadata["changelog_uri"] = "https://github.com/nickhammond/buttondown/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git])
    end
  end

  spec.require_paths = ["lib"]
end
