# Smile ID Ruby SDK Example

This repository is a small CLI application that demonstrates the public `usesmileid` Ruby SDK.

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
gem 'usesmileid', path: '..'
```

## Configuration

```bash
export SMILE_PARTNER_ID="2"
export SMILE_API_KEY="..."
export SMILE_BASE_URL="https://devapi.smileidentity.com"   # optional host override
export SMILE_CALLBACK_URL="https://your-app.example.com/smile-callback"
```

Partner ids are displayed zero-padded (for example 002) but must be passed without leading zeros (2).

`SMILE_BASE_URL` overrides the SDK environment URL. The SDK only names two environments, sandbox and production, so use it to reach any other host such as devapi.

Optional:

- `SMILE_TIMEOUT` sets the per-request timeout in seconds.

## Commands

```bash
bundle exec exe/smileid-example-ruby services --country NG
bundle exec exe/smileid-example-ruby enhanced-kyc --country NG --id-type NIN --id-number 12345678901 --given-names "Amina Fatou" --last-name Clearwater --email amina.clearwater@example.com --privacy-url https://your-app.example.com/privacy
bundle exec exe/smileid-example-ruby status --job-id job_...
bundle exec exe/smileid-example-ruby replay --job-id job_... --callback-url https://your-app.example.com/smile-callback
```

Non-production environments match test identities on given names + last name + email; an unrecognised identity resolves to `block`.

## Development

```bash
bundle exec rspec
bundle exec rubocop
```
