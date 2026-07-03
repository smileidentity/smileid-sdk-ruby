# Smile ID Ruby SDK Example

This repository is a small CLI application that demonstrates the public `smileid` Ruby SDK.

It also acts as a testbench: specs run the same CLI code against a Faraday test adapter and verify the SDK sends the expected requests.

## Requirements

- Ruby 3.0 or later.
- Smile ID sandbox credentials for real API calls.

## Setup

```bash
bundle install
```

The Gemfile uses the sibling SDK checkout:

```ruby
gem 'smileid', path: '..'
```

## Configuration

```bash
export SMILE_PARTNER_ID="12345"
export SMILE_API_KEY="..."
export SMILE_CALLBACK_URL="https://your-app.example.com/smile-callback"
```

Optional:

- `SMILE_BASE_URL` overrides the SDK environment URL.
- `SMILE_TIMEOUT` sets the per-request timeout in seconds.

## Commands

```bash
bundle exec exe/smileid-example-ruby services --country NG
bundle exec exe/smileid-example-ruby enhanced-kyc --country NG --id-type NIN --id-number 12345678901 --given-names Amina --last-name Okafor --email amina@example.com --privacy-url https://your-app.example.com/privacy
bundle exec exe/smileid-example-ruby status --job-id job_...
bundle exec exe/smileid-example-ruby replay --job-id job_... --callback-url https://your-app.example.com/smile-callback
```

## Development

```bash
bundle exec rspec
bundle exec rubocop
```
