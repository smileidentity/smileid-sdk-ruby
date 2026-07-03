# AGENTS.md

This repository holds Smile ID's server-side SDK for Ruby, covering the V3 APIs.

## Source of truth

The API surface — endpoints, request shapes, response shapes — comes from the OpenAPI specifications published at https://github.com/smileidentity/api-reference. Treat that repository as authoritative. Do not hand-write request or response models that duplicate what the specs already define.

## Layout

- `lib/smileid/generated/` contains the current generated-layer request/response tables. Treat it as generator-owned when a generator is available; until then, keep edits tightly scoped and mirrored in tests.
- `lib/smileid/client/` contains hand-written client code that wraps the generated layer.
- `lib/smileid/errors.rb` contains hand-written error classes.
- `lib/smileid/helpers/` contains hand-written helper utilities.

## Running tests

Install dependencies and run the test suite with:

```bash
bundle install
bundle exec rspec
```

## Org-wide agent conventions

Internal contributors should also read the shared agent conventions at https://github.com/smileidentity/agents (a private repository).
