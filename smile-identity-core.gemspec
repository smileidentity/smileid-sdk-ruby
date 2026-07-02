# frozen_string_literal: true

require_relative 'lib/smileid/version'

Gem::Specification.new do |spec|
  spec.name = 'smile-identity-core'
  spec.version = SmileID::VERSION
  spec.authors = ['Smile Identity']
  spec.email = ['support@smileidentity.com']

  spec.summary = 'Official Smile ID server-side SDK for Ruby.'
  spec.description = 'Server-side SDK for integrating with the Smile Identity V3 APIs.'
  spec.homepage = 'https://github.com/smileidentity/smileid-sdk-ruby'
  spec.required_ruby_version = '>= 3.0'
  spec.license = 'MIT'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler-audit', '~> 0.9'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.60'
end
