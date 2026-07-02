# AGENTS.md

This repository holds Smile ID's server-side SDK for Ruby, covering the V3 APIs.

## Source of truth

The API surface — endpoints, request shapes, response shapes — comes from the OpenAPI specifications published at https://github.com/smileidentity/api-reference. Treat that repository as authoritative. Do not hand-write request or response models that duplicate what the specs already define.

## Layout

- `lib/smileid/generated/` will hold code produced by the generator. It's owned by the generation pipeline — don't hand-edit it, regenerate it instead.
- `lib/smileid/client/` will hold hand-written client code that wraps the generated layer.
- `lib/smileid/errors/` will hold hand-written error classes.
- `lib/smileid/helpers/` will hold hand-written helper utilities.

These directories don't exist yet in this scaffold. They'll be added as the SDK is built out.

## Running tests

Install dependencies and run the test suite with:

```bash
bundle install
bundle exec rspec
```

## Org-wide agent conventions

Internal contributors should also read the shared agent conventions at https://github.com/smileidentity/agents (a private repository).
