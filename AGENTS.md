# AGENTS.md

This repository holds Smile ID's server-side SDK for Ruby, covering the V3 APIs.

## Source of truth

The API surface — endpoints, request shapes, response shapes — comes from the OpenAPI specifications published at https://github.com/smileidentity/api-reference. Treat that repository as authoritative. Do not hand-write request or response models that duplicate what the specs already define.

## Layout

- `lib/usesmileid.rb` loads the `SmileID` module. The gem name and require path are both `usesmileid`.
- `lib/usesmileid/generated/` holds wire models and the per-operation table. A generator will own it later, so put defaults and convenience logic in `lib/usesmileid/client/resources.rb`, not here.
- `lib/usesmileid/client/` holds the hand-written client, config, token handling, transport and resource namespaces.
- `lib/usesmileid/errors.rb` holds the `SmileID::Errors` hierarchy.
- `lib/usesmileid/helpers/` holds the consent, multipart and user-details helpers.

## Running tests

Install dependencies and run the test suite with:

```bash
bundle install
bundle exec rspec
```

CI runs `bundler-audit` as "Security Audit" on pull requests that touch `Gemfile`, `Gemfile.lock` or the gemspec, and daily on `main`, where a failure opens an issue labelled `security-audit`. Run it locally with `bundle exec bundler-audit update && bundle exec bundler-audit check`. Fix a flagged transitive gem, such as `json`, with `bundle update <gem> --conservative`.

The sandbox e2e spec skips unless `SMILE_PARTNER_ID` and `SMILE_API_KEY` are set. CI runs it on pushes to `main` and nightly, not on pull requests. If it skipped locally, say "not run against sandbox" in the pull request.

## Org-wide agent conventions

Internal contributors should also read the shared agent conventions at https://github.com/smileidentity/agents (a private repository).
