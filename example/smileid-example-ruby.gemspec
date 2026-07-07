# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'smileid-example-ruby'
  spec.version = '0.1.0'
  spec.summary = 'Example CLI and integration testbench for the Smile ID Ruby SDK.'
  spec.authors = ['Smile Identity']
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'
  spec.files = Dir['lib/**/*.rb', 'exe/*', 'README.md']
  spec.bindir = 'exe'
  spec.executables = ['smileid-example-ruby']
  spec.require_paths = ['lib']
  spec.add_dependency 'smileid'
end
