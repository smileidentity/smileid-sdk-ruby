# AGENTS.md

This repository is a standalone example application for the Smile ID Ruby SDK.

## Development rules

- Use only the public `SmileID` SDK API.
- Keep specs deterministic with Faraday test adapters; do not require real Smile ID credentials.
- Keep credentials out of source control and docs.
- Run `bundle exec rspec` before handing off changes.

## Layout

- `lib/smileid_example.rb` contains command parsing and SDK calls.
- `exe/smileid-example-ruby` is the CLI entrypoint.
- `spec/smileid_example_spec.rb` is the SDK testbench.
- `.github/workflows/ci.yml` runs RSpec, RuboCop, and Semgrep.
