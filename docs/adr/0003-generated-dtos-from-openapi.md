# 0003. DTOs generated from the OpenAPI spec, never hand-written

- **Status**: Accepted
- **Date**: 2026-09-01 (recorded retroactively 2026-10-12)

## Context

The Engelsystem REST API publishes an OpenAPI 3.0.3 spec, and it is
still in beta and changes (new endpoints and fields arrived during this
project). Hand-written models would drift from the server.

## Decision

Generate the DTOs with OpenAPI Generator (`swift5`, `library=urlsession`,
`responseAs=AsyncAwait`) from `EngelsystemClientKit/Resources/openapi.yml`
via `Scripts/generate-api.sh`. Never edit `Generated/`; changes belong in
`openapi.yml` or in a mapping layer outside `Generated/`. For
not-yet-merged server branches, fetch the branch's `openapi.yml` instead
of hand-writing schemas.

## Consequences

- Spec changes are one regeneration away; the client cannot silently
  diverge from the documented API.
- Generated names can collide with generator boilerplate (e.g.
  `ValidationError` → `ApiValidationError`).
- Details: [`../architecture.md`](../architecture.md) (Tech stack, API).
