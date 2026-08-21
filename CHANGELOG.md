# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Client

- Sandbox and production environments, with a `base_url` override for other
  hosts.
- Typed errors under `SmileID::Errors`, keyed on HTTP status.

[Unreleased]: https://github.com/smileidentity/smileid-sdk-ruby/compare/v12.0.0...HEAD
[12.0.0]: https://github.com/smileidentity/smileid-sdk-ruby/releases/tag/v12.0.0
