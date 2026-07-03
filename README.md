# smileid

[![Gem Version](https://img.shields.io/gem/v/smileid.svg)](https://rubygems.org/gems/smileid)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Official Smile ID server-side SDK for Ruby, covering the V3 APIs.

The SDK handles authentication, request serialization, retries and typed errors so you can call Smile ID from Ruby with plain method calls. You never handle tokens yourself.

Requires Ruby 3.0 or later.

## Installation

Add the gem to your Gemfile:

```ruby
gem "smileid"
```

Or install it directly:

```bash
gem install smileid
```

## Getting started

Construct one client with your partner id and API key. The client is thread-safe and can be shared across your application.

```ruby
require "smileid"

smile = SmileID::Client.new(
  partner_id: "1234",
  api_key: ENV.fetch("SMILE_API_KEY"),
  environment: :sandbox,                              # default
  default_callback_url: "https://app.example.com/cb"  # optional
)
```

Authentication is internal: the SDK fetches a short-lived token from the API, caches it until just before expiry, and refreshes it once automatically if a request returns 401. You never see or pass a token.

### Environment selection

The client uses the sandbox by default. Set `environment: :production` to go live, or pass an explicit `base_url:` to override the host entirely (it wins over `environment`). Only `:sandbox` and `:production` are accepted.

A custom `base_url` must be an absolute https URL with no query string or fragment. There is deliberately no way to use plain http. Callback URLs (`default_callback_url` and any per-request `callback_url`) must also be https; an insecure callback raises a validation error before any request is sent.

| Environment | Base URL |
|---|---|
| `:sandbox` (default) | `https://testapi.smileidentity.com` |
| `:production` | `https://api.smileidentity.com` |

### Other client options

| Option | Default | Purpose |
|---|---|---|
| `timeout` | 30 | Per-request timeout in seconds. Every method also accepts a per-call `timeout:` override. |
| `max_retries` | 2 | Retries for idempotent calls only (status and services reads, and the internal token fetch). Job submissions are never retried automatically. |
| `http_client` | SDK default | Inject your own `Faraday::Connection` for testing or proxies. |

## Shared inputs

All verification submissions need consent and user details.

```ruby
consent = SmileID::Consent.granted(
  granted_at: Time.now.utc,
  notice_language: "EN",
  notice_privacy_policy_url: "https://example.com/privacy"
)

user_details = {
  given_names: "John",
  last_name: "Doe",
  email: "john@example.com"   # at least one of email / phone_number is required
}
```

Image inputs accept a file path (`"selfie.jpg"`), raw bytes, an IO object, or a hash such as `{ path: "front.png", content_type: "image/png" }`.

## Methods

### Enhanced KYC

```ruby
accepted = smile.enhanced_kyc.verify(
  country: "NG",
  id_type: "NIN",
  id_number: "12345678901",
  user_details: user_details,
  consent: consent,
  user_id: "user_01h8x9y2z3a4b5c6d7e8f9g0h1"  # optional
)
accepted.job_id     # => "job_..."
accepted.accepted?  # => true
```

### Document verification

```ruby
accepted = smile.documents.verify(
  selfie_image: "selfie.jpg",
  liveness_images: ["live1.jpg", "live2.jpg", "live3.jpg",
                    "live4.jpg", "live5.jpg", "live6.jpg"],
  document: "doc_front.jpg",
  document_back: "doc_back.jpg",  # optional
  country: "NG",
  user_details: user_details,
  consent: consent
)
```

### Enhanced document verification

Same shape as document verification, but `id_type` is required.

```ruby
accepted = smile.documents.verify_enhanced(
  id_type: "PASSPORT",
  selfie_image: "selfie.jpg",
  liveness_images: ["live1.jpg", "live2.jpg", "live3.jpg",
                    "live4.jpg", "live5.jpg", "live6.jpg"],
  document: "doc_front.jpg",
  country: "NG",
  user_details: user_details,
  consent: consent
)
```

### Biometric KYC

```ruby
accepted = smile.biometric_kyc.verify(
  selfie_image: "selfie.jpg",
  liveness_images: ["live1.jpg", "live2.jpg", "live3.jpg",
                    "live4.jpg", "live5.jpg", "live6.jpg"],
  country: "NG",
  id_type: "NIN",
  id_number: "12345678901",
  user_details: user_details,
  consent: consent
)
```

### Biometric enrollment

```ruby
accepted = smile.biometric.enroll(
  selfie_image: "selfie.jpg",
  liveness_images: ["live1.jpg", "live2.jpg", "live3.jpg",
                    "live4.jpg", "live5.jpg", "live6.jpg"],
  user_details: user_details,
  consent: consent,
  user_id: "user-42"  # optional partner-provided id
)
```

### Biometric authentication

`user_id` is required and must match an enrolled user. Images are required unless you set `use_enrolled_image: true`.

```ruby
accepted = smile.biometric.authenticate(
  user_id: "user-42",
  selfie_image: "selfie.jpg",
  liveness_images: ["live1.jpg", "live2.jpg", "live3.jpg",
                    "live4.jpg", "live5.jpg", "live6.jpg"],
  user_details: user_details,
  consent: consent
)
```

### Biometric compare

```ruby
accepted = smile.biometric.compare(
  selfie_image: "selfie.jpg",
  comparison_image: "id_photo.jpg",
  comparison_image_type: "ID_PHOTO",  # DOCUMENT | ID_PHOTO | PORTRAIT
  user_details: user_details,
  consent: consent
)
```

### Check a verification's status

```ruby
status = smile.verifications.retrieve("job_01h8x9y2z3a4b5c6d7e8f9g0h1")
status.status      # "complete", "processing" or "not_found"
status.complete?   # true when terminal
status.message     # e.g. "Verification completed with state: clear"
```

A job the API does not know yet returns a status of `not_found` rather than raising an error, so you can poll safely right after submission.

### Wait for a verification to complete

```ruby
status = smile.verifications.wait_until_complete(
  "job_01h8x9y2z3a4b5c6d7e8f9g0h1",
  interval: 2,   # seconds between polls (default 2)
  timeout: 60    # give up after this many seconds (default 60)
)
```

Raises `SmileID::Errors::TimeoutError` if the job does not complete in time. Pass `treat_not_found_as_pending: false` to return immediately when the job is unknown instead of polling on.

### Replay a callback

```ruby
smile.verifications.replay(
  "job_01h8x9y2z3a4b5c6d7e8f9g0h1",
  callback_url: "https://app.example.com/cb"  # optional override
)
```

Replaying a job that is still processing raises `SmileID::Errors::ConflictError`.

### Report user fraud

```ruby
smile.users.report_fraud(
  "user-42",
  is_fraud: true,
  reason: "ACCOUNT_TAKEOVER",
  reported_by: "risk@example.com"
)
```

Or use the convenience wrappers:

```ruby
smile.users.flag_fraud("user-42", reason: "ACCOUNT_TAKEOVER", reported_by: "risk@example.com")
smile.users.clear_fraud("user-42", notes: "Cleared after review", reported_by: "risk@example.com")
```

When flagging, `reason` is required (and `notes` too if the reason is `OTHER`). When clearing, `notes` is required.

### Services

Bank codes, supported ID types and supported documents need no authentication.

```ruby
smile.services.bank_codes(country: "NG").bank_codes
# => [{ "code" => "044", "country" => "NG", "name" => "Access Bank" }, ...]

smile.services.supported_id_types(country: "NG").id_types
# => [{ "country" => "NG", "type" => "BVN", "label" => ..., "regex" => ..., ... }, ...]

smile.services.supported_documents(country_code: "NG").valid_documents
# => [{ "country" => { "code" => "NG", ... }, "id_types" => [...] }, ...]

smile.services.id_status(country: "NG", id_type: "BVN")
# => #<IdStatusResponse last_known_status="online" last_hour_success_rate="95%" ...>
```

## Error handling

Every API failure raises a typed error under `SmileID::Errors`, keyed on the HTTP status:

| Error | Raised on |
|---|---|
| `InvalidRequestError` | 400, 415, and failed client-side validation (`ValidationError` subclass) |
| `AuthenticationError` | 401 after one automatic token refresh |
| `PaymentRequiredError` | 402 — insufficient wallet balance |
| `PermissionError` | 403 |
| `NotFoundError` | 404 (except `verifications.retrieve`, which returns a `not_found` status) |
| `ConflictError` | 409 — for example replaying a job that is still processing |
| `PayloadTooLargeError` | 413 |
| `RateLimitError` | 429 |
| `APIError` | any 5xx |
| `ConnectionError` | network failure or timeout with no HTTP response |
| `TimeoutError` | `wait_until_complete` deadline passed (no HTTP response) |
| `UnexpectedResponseError` | a 2xx response whose body is not the expected JSON object, for example proxy interference |

Each error exposes `status_code`, `status`, `message`, `code`, `request_id` and `raw_body`.

```ruby
begin
  smile.enhanced_kyc.verify(...)
rescue SmileID::Errors::PaymentRequiredError => e
  e.status_code  # 402
  e.message      # "Insufficient wallet balance."
rescue SmileID::Errors::SmileIDError => e
  # catch-all for anything the API raised
end
```

## Telemetry

The SDK sends three telemetry headers on every request: `SmileID-Source-SDK` (`ruby`), `SmileID-Source-SDK-Version` and a `User-Agent` identifying the SDK and Ruby version. These identify the SDK for observability. They are never used for authentication and carry no personal data.

## Development

```bash
bundle install
bundle exec rspec     # unit tests, fully offline
bundle exec rubocop
```

The end-to-end sandbox test runs only when `SMILE_PARTNER_ID` and `SMILE_API_KEY` are set in the environment; otherwise it skips.

## Contributing

See [SECURITY.md](SECURITY.md) for how to report a security issue.
