# frozen_string_literal: true

require_relative "lib/ttl_memoizeable/version"

Gem::Specification.new do |spec|
  spec.name = "ttl_memoizeable"
  spec.version = TTLMemoizeable::VERSION
  spec.authors = ["Daniel Westendorf"]
  spec.email = ["daniel@prowestech.com"]

  spec.summary = "Cross-thread memoization in ruby with eventual consistency."
  spec.description = "A sharp knife for cross-thread memoization providing eventual consistency."
  spec.homepage = "https://github.com/huntresslabs/ttl_memoizeable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport"

  spec.add_development_dependency "bump"
end
