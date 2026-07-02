# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in smile-identity-core.gemspec
gemspec

group :development, :test do
  gem 'bundler-audit', '~> 0.9', require: false
  # Transitive dependency of webmock; 7.x needs Ruby 3.2, but CI tests Ruby 3.0.
  gem 'public_suffix', '< 7'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', '~> 1.60'
  gem 'webmock', '~> 3.0', require: false
end
