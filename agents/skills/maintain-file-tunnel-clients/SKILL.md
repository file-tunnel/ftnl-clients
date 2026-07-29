---
name: maintain-file-tunnel-clients
description: Maintain the official Rust, TypeScript, Dart, and Gleam File Tunnel SDKs as one wire-compatible family. Use when adding or changing endpoints, types, events, retry behavior, capability handling, package metadata, tests, or release-facing client behavior.
---

# Maintain File Tunnel clients

## Start from the contract

Read `ftnl-interfaces` before changing a wire shape. Update OpenAPI, AsyncAPI,
JSON Schema, and fixtures there first when the protocol itself changes. Do not
invent a client-only request or event format.

Map each operation across `clients/rust`, `clients/typescript`, `clients/dart`,
and `clients/gleam`. Keep the same capabilities available unless a runtime
limitation is documented; keep public names idiomatic to each language.

## Make the change

1. Add or update contract fixtures before implementation behavior.
2. Implement the narrowest package first and add a focused failure-path test.
3. Port the behavior to the other packages without copying runtime-specific
   transport assumptions.
4. Verify capability redaction, URI construction, status/error mapping, and
   reconnect behavior in every affected runtime.
5. Update the root compatibility table or examples when a public surface
   changes.

Gleam intentionally returns request values rather than selecting a BEAM or
JavaScript transport. Preserve that boundary.

## Guard invariants

- Never treat a tunnel UUID as authorization.
- Never expose capabilities in URLs, logs, debug output, arbitrary response
  bodies, or default persistence.
- Keep pairing secrets fragment-only and event tickets one-time and short-lived.
- Surface ambiguous outcomes instead of hiding unsafe retries.
- Reconcile event sequence gaps through snapshots.
- Keep upload byte paths distinct from sync metadata; `ftnl-sync` must never
  replicate file bytes or capabilities.

## Validate the family

```bash
(cd clients/rust && cargo fmt --all -- --check && cargo clippy --locked --all-targets -- -D warnings && cargo test --locked)
(cd clients/typescript && npm ci && npm test)
(cd clients/dart && dart pub get && dart format --output=none --set-exit-if-changed lib test && dart analyze && dart test)
(cd clients/gleam && gleam format --check src test && gleam deps download && gleam test)
```

Run `ftnl-e2e` after any change to pairing, upload, download, event ordering, or
cancellation.
