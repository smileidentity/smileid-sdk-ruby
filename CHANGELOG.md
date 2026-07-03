# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Renamed the gem from `smile-identity-core` to `smileid`. The require path
  (`require "smileid"`) and the `SmileID` module are unchanged.
- Set the version to 12.0.0, aligning the server SDKs with the V12 mobile
  SDKs.

### Added

- Full V3 API coverage: enhanced KYC, document verification, enhanced document
  verification, biometric KYC, biometric enrollment, authentication and compare,
  verification status with a `wait_until_complete` polling helper, callback
  replay, fraud reporting (with `flag_fraud` / `clear_fraud` wrappers), and the
  four services endpoints.
- Internal JWT authentication with a thread-safe cache and a single automatic
  refresh on 401.
- Typed error hierarchy under `SmileID::Errors`, covering both API error body
  shapes.
- Automatic retries with exponential backoff and `Retry-After` support for
  idempotent calls only.
- Consent builder and client-side validation for user details and fraud
  reports.
- Optional HMAC request signing, off unless `partner_secret` is configured.
