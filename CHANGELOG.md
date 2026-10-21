# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [12.2.0] - 2026-10-08

### Changed

- Each request mints its own token, bound to that request's `user_id` and product, instead of reusing one cached token. A 401 is no longer retried with a refreshed token.
- A `user_id` that is empty or padded with whitespace raises `ValidationError` before any request is sent.
- `biometric.authenticate` takes `selfie_image:` and `liveness_images:` as required keywords.

### Added

- `biometric_kyc.verify(use_enrolled_image: true, user_id: ...)` verifies against the user's enrolled selfie; the grant is bound into the job's token and the selfie and liveness images may be omitted.

### Removed

- `use_enrolled_image` from `biometric.authenticate`; selfie and liveness images are now always required.

## [12.1.0] - 2026-10-01

### Added

- Residency Document Verification: `documents.verify_residency`.

## [12.0.0] - 2026-08-20

First public release.

### Products

- Enhanced KYC, Biometric KYC, Document Verification and Enhanced Document
  Verification.
- SmartSelfie enrollment, authentication and compare.

### Verifications

- Job status retrieval, plus a `wait_until_complete` helper that polls until
  a job reaches a terminal decision.
- Callback replay.
- User fraud reporting, with `flag_fraud` / `clear_fraud` convenience
  wrappers.

### Client

- Sandbox and production environments, with a `base_url` override for other
  hosts. `base_url` and callback URLs must be https, checked before any
  request is sent.
- Internal JWT authentication, cached and refreshed automatically on 401.
- Automatic retries with backoff for idempotent calls.
- Typed errors under `SmileID::Errors`, keyed on HTTP status.
- Bank codes, supported ID types and supported documents lookups.

[Unreleased]: https://github.com/smileidentity/smileid-sdk-ruby/compare/v12.2.0...HEAD
[12.2.0]: https://github.com/smileidentity/smileid-sdk-ruby/compare/v12.1.0...v12.2.0
[12.1.0]: https://github.com/smileidentity/smileid-sdk-ruby/compare/v12.0.0...v12.1.0
[12.0.0]: https://github.com/smileidentity/smileid-sdk-ruby/releases/tag/v12.0.0
