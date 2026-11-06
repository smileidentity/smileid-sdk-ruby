# AGENTS.md

This repository holds Smile ID's server-side SDK for Ruby, covering the V3 APIs.

## Source of truth

The API surface (endpoints, request and response shapes) comes from `specs/v3/openapi.yaml` in [smileidentity/api-reference](https://github.com/smileidentity/api-reference). Read it at a release tag such as `v3.1115.0`, not at `main`. When a task or pull request names a tag, use that one. When the SDK and the spec disagree, the spec wins.

- Ignore anything marked `x-smile-sdk-exclude: true`. These are server-to-server details, such as the HMAC signature headers, that the SDKs leave out on purpose.
- Don't add endpoints or fields that aren't in the spec. Internal endpoints are kept out of it on purpose.

## Layout

- `lib/usesmileid.rb` loads the `SmileID` module. The gem name and require path are both `usesmileid`.
- `lib/usesmileid/generated/` holds wire models and the per-operation table. It is hand-written for now, because there is no generator yet. Edit it by hand, but keep it shaped like generator output: wire models and one thin function per operation, with no business logic. Put defaults and convenience logic in `lib/usesmileid/client/resources.rb` instead. A generator will replace it later.
- `lib/usesmileid/client/` holds the hand-written client, config, token handling, transport and resource namespaces.
- `lib/usesmileid/errors.rb` holds the `SmileID::Errors` hierarchy.
- `lib/usesmileid/helpers/` holds the consent, multipart and user-details helpers.

## Keeping the SDKs in step

This SDK is one of the `smileid-sdk-*` repositories, which share one design. A change to the public API here should be made the same way in the others: the same operations, option names and defaults, adjusted only for each language's naming conventions.

Automated pull requests use these labels and branches:

| Label | Branch | Meaning |
|---|---|---|
| `spec-sync` | `bot/spec-sync` | Brings the SDK up to a new spec tag. One rolling pull request at a time. |
| `breaking` | `bot/spec-sync-breaking-<tag>` | A change that needs a major release. Breaking changes always get their own pull request. |
| `parity-port` | `bot/parity-port-<repo>-<number>` | A change ported from another SDK's merged pull request, which it links to. |
| `release` | `bot/release-v<version>` | A version bump and changelog entry. |

Add `parity:skip` to a pull request that should not be ported to the other SDKs.

Tests:

- Every new operation needs a golden fixture test, which checks the exact request body and headers, and tests that parse its responses.
- Changed lines must be fully covered by tests. Don't add coverage exclusion comments.

## Running tests

Install dependencies and run the test suite with:

```bash
bundle install
bundle exec rspec
```

CI runs `bundler-audit` as "Security Audit" on pull requests that touch `Gemfile`, `Gemfile.lock` or the gemspec, and daily on `main`. A failed daily run only shows as red: its issue step needs the `security-audit` and `priority:high` labels, which do not exist in this repo (as of October 2026), so it opens no issue. Run it locally with `bundle exec bundler-audit update && bundle exec bundler-audit check`. Fix a flagged transitive gem, such as `json`, with `bundle update <gem> --conservative`.

The sandbox e2e spec skips unless `SMILE_PARTNER_ID` and `SMILE_API_KEY` are set. CI runs it on pushes to `main` and nightly, not on pull requests. If it skipped locally, say "not run against sandbox" in the pull request.

## Org-wide agent conventions

Internal contributors should also read the shared agent conventions at https://github.com/smileidentity/agents (a private repository).
