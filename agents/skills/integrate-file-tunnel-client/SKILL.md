---
name: integrate-file-tunnel-client
description: Integrate the official File Tunnel SDK into a web, desktop, mobile, backend, or Gleam application. Use when selecting the Rust, TypeScript, Dart, or Gleam client; implementing the desktop-to-phone QR handoff; consuming upload progress; downloading completed files; or handling reconnects safely.
---

# Integrate a File Tunnel client

## Choose the package

- Use `clients/typescript` for browser or TypeScript desktop surfaces.
- Use `clients/rust` for native Rust applications and services.
- Use `clients/dart` for Dart and Flutter applications.
- Use `clients/gleam` when the host should execute transport-neutral HTTP request builders.

Read the selected package source and tests before copying an example. Confirm that
the deployed API implements the matching contract from `ftnl-interfaces`.

## Implement the handoff

1. Create a bounded tunnel from the desktop-side application.
2. Render the returned `pairing_uri` as the QR payload. Keep the desktop
   capability in memory.
3. Let the phone portal exchange the fragment-only pairing secret for its phone
   capability and upload declared files.
4. Mint a one-time event ticket and subscribe to progress events. If an event
   sequence skips, fetch a fresh snapshot before updating UI state.
5. Download only files whose snapshot/event state is complete, verify expected
   size or digest when the host has one, then cancel or allow the tunnel to
   expire.

Keep phone and desktop responsibilities separate. Do not send the desktop
capability to the portal or claim a tunnel from the desktop.

## Preserve security

- Treat the UUID as routing data, not authentication.
- Send capabilities only in authorization headers. Never place them in query
  strings, logs, analytics, crash reports, or ordinary persistence.
- Keep the one-time pairing secret in the URI fragment. Remove it from visible
  browser state after claim.
- Use HTTPS/WSS outside local development.
- Bound file count, size, and accepted media types in both host UX and API
  requests.
- Supply a stable idempotency key before retrying tunnel creation or file
  declaration. Do not replay an ambiguous whole-file upload.

## Validate

Run the selected package's native checks from the repository root:

```bash
(cd clients/rust && cargo test --locked)
(cd clients/typescript && npm ci && npm test)
(cd clients/dart && dart pub get && dart analyze && dart test)
(cd clients/gleam && gleam deps download && gleam test)
```

For a complete application integration, also run the two-device journey in
`ftnl-e2e`.
