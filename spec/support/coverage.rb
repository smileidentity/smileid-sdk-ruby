# frozen_string_literal: true

# Line and branch coverage for lib/, written to coverage/ as HTML and as
# Cobertura XML (coverage/coverage.xml) for diff-cover. Loaded by
# spec_helper.rb when COVERAGE is set, before the SDK is required.
#
# lib/usesmileid/generated/ must stay at 100% line and branch coverage. A
# generator will own that directory, and every model and operation it writes
# must be exercised by a test.

require 'simplecov'
require 'simplecov-cobertura'

GENERATED_DIR = 'lib/usesmileid/generated/'

SimpleCov.start do
  enable_coverage :branch
  track_files 'lib/**/*.rb'
  add_filter '/spec/'
  add_filter '/scripts/'
  add_group 'Generated', GENERATED_DIR
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::CoberturaFormatter]
  )
end

SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!

  generated = result.files.select { |file| file.project_filename.start_with?("/#{GENERATED_DIR}") }
  gaps = generated.flat_map do |file|
    lines = file.missed_lines.map { |line| "#{file.project_filename}:#{line.number} line not covered" }
    branches = file.missed_branches.map do |branch|
      "#{file.project_filename}:#{branch.start_line} #{branch.type} branch not covered"
    end
    lines + branches
  end

  if generated.empty?
    warn "Coverage: no files found under #{GENERATED_DIR}"
    Kernel.exit(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
  elsif gaps.any?
    warn "Coverage: #{GENERATED_DIR} must have 100% line and branch coverage. Not covered:"
    gaps.each { |gap| warn "  #{gap}" }
    Kernel.exit(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
  end
end
