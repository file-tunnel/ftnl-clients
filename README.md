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

The root [`.zpkg.toml`](.zpkg.toml) also makes this repository a
[`zed-pkg`](https://github.com/zed-pkg) package. Zed produces one complete
source snapshot plus independently re-rooted Node.js, Rust, Dart, and Gleam
artifacts. CI packs every target and exercises publish planning without
uploading.

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

## Transport safety

All clients reject public `http://` endpoints before a capability can be sent.
Cleartext remains available for loopback, private/link-local addresses,
single-label service names, and the documented `.svc.cluster.local` and
`.internal` trust boundaries. Use `https://` for every public deployment.

| Client | Request timeout | Redirect handling |
|---|---|---|
| Rust | 30 seconds by default; `FileTunnelClient::with_timeout` overrides it | disabled |
| TypeScript | 30 seconds by default; `timeoutMs` overrides it | rejected |
| Dart | 30 seconds by default; `requestTimeout` overrides it | disabled |
| Gleam | owned by the caller-selected transport | owned by the caller-selected transport |

Timeouts surface to the host instead of triggering hidden retries. The Gleam
package intentionally returns transport-neutral requests, so the BEAM or
JavaScript executor must apply a finite timeout and refuse redirects before it
sends the request.

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
nix develop --command agent-check
```

The root flake pins all four language toolchains and the automation linters.
The formal-boundary workflow generates arbitrary UTF-8 pairing secrets and
checks that Rust accepts them only from the URI fragment, never from query
parameters.
AI agents should begin with [`agents.md`](agents.md), which routes integration
and maintainer work to the skills under `agents/skills/`.

MIT licensed.
