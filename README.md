# ftnl-clients

Official File Tunnel clients for Rust, TypeScript, Dart, and Gleam. The layout
follows the multi-language SDK pattern used by `fiducia-clients`,
`cliptown-clients`, and `opto-sync-clients`, with a deliberately small,
consistent surface in every language.

## Packages

| Language | Directory | Package |
|---|---|---|
| Rust | `clients/rust` | `ftnl-client` |
| TypeScript | `clients/typescript` | `@file-tunnel/client` |
| Dart | `clients/dart` | `ftnl_client` |
| Gleam | `clients/gleam` | `ftnl_client` |

Each client covers:

- create a tunnel;
- exchange a one-time phone pairing secret;
- fetch a snapshot after reconnect or event gaps;
- declare an upload;
- upload/download bytes;
- mint a one-time realtime ticket;
- build or connect the ticket-authenticated WebSocket endpoint;
- cancel the tunnel.

SDKs intentionally do not persist capabilities. Host apps decide whether a
capability may survive process restart and must use platform secure storage if
it does. Logs and error values redact authorization data.

The canonical wire contract lives in
[`ftnl-interfaces`](https://github.com/file-tunnel/ftnl-interfaces). Types are
kept locally reviewable during bootstrap; CI contract fixtures are designed to
move to generated packages once the first version is published.

## Retry policy

Creating tunnels and declaring files may be retried only with an idempotency
key. Upload retry should use the future multipart/resume contract; replaying a
whole upload is safe only while a declared slot has no published content.
Clients do not hide retries because an ambiguous timeout needs host UX.

## Validate

```bash
(cd clients/rust && cargo test)
(cd clients/typescript && npm install && npm test)
(cd clients/dart && dart pub get && dart analyze && dart test)
(cd clients/gleam && gleam deps download && gleam test)
```

MIT licensed.
