# frozen_string_literal: true

require_relative "lib/buttondown/version"

Gem::Specification.new do |spec|
  spec.name = "buttondown"
  spec.version = Buttondown::VERSION
  spec.authors = ["Nick Kelly"]
  spec.email = ["nick@fromthekeyboard.com"]

  spec.summary = "Ruby client for the Buttondown newsletter API"
  spec.description = "A Ruby client for the Buttondown newsletter API."
  spec.homepage = "https://github.com/nickhammond/buttondown"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nickhammond/buttondown"
  spec.metadata["changelog_uri"] = "https://github.com/nickhammond/buttondown/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/nickhammond/buttondown/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Only lib/ and the docs a reader might want ship in the gem. Everything else
  # tracked here is development tooling, which costs the installer bytes and
  # tells them nothing. The `.git` prefix also covers `.gitignore`.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == File.expand_path(__FILE__)) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git]) ||
        %w[AGENTS.md .rubocop.yml .undercover Gemfile Guardfile Rakefile].include?(f)
    end
  end

  spec.require_paths = ["lib"]
end
