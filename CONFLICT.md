# file-tunnel/ftnl-clients#21 — chore: nightly polyglot client hardening

head: automation/nightly-client-hardening  base: main  author: ORESoftware  updated: 2026-08-28T22:26:24Z
dir: /Users/maca5/codes/.claude-fleet/scratch/merge/file-tunnel_ftnl-clients__21

## conflicted files
- .zpkg.toml
- clients/.api-surface.sha256
- clients/c/.zed-api-surface.sha256
- clients/c/.zed-client-contract.json
- clients/contract-manifest.json
- clients/cpp/.zed-api-surface.sha256
- clients/cpp/.zed-client-contract.json
- clients/dart/.zed-api-surface.sha256
- clients/dart/.zed-client-contract.json
- clients/elixir/.zed-api-surface.sha256
- clients/elixir/.zed-client-contract.json
- clients/erlang/.zed-api-surface.sha256
- clients/erlang/.zed-client-contract.json
- clients/gleam/.zed-api-surface.sha256
- clients/gleam/.zed-client-contract.json
- clients/go/.zed-api-surface.sha256
- clients/go/.zed-client-contract.json
- clients/java/.zed-api-surface.sha256
- clients/java/.zed-client-contract.json
- clients/kotlin/.zed-api-surface.sha256
- clients/kotlin/.zed-client-contract.json
- clients/php/.zed-api-surface.sha256
- clients/php/.zed-client-contract.json
- clients/python/.zed-api-surface.sha256
- clients/python/.zed-client-contract.json
- clients/ruby/.zed-api-surface.sha256
- clients/ruby/.zed-client-contract.json
- clients/rust/.zed-api-surface.sha256
- clients/rust/.zed-client-contract.json
- clients/swift/.zed-api-surface.sha256
- clients/swift/.zed-client-contract.json
- clients/typescript/.zed-contracts/nodejs/.zed-api-surface.sha256
- clients/typescript/.zed-contracts/nodejs/.zed-client-contract.json
- clients/typescript/bun/.zed-api-surface.sha256
- clients/typescript/bun/.zed-client-contract.json
- clients/typescript/deno/.zed-api-surface.sha256
- clients/typescript/deno/.zed-client-contract.json
- clients/typescript/edge/.zed-api-surface.sha256
- clients/typescript/edge/.zed-client-contract.json
- clients/wasm/.zed-api-surface.sha256
- clients/wasm/.zed-client-contract.json
- clients/zig/.zed-api-surface.sha256
- clients/zig/.zed-client-contract.json

## base (main) last 8 commits
2877d83 feat(validation): consume public lib-core SDKs (#35)
f7522ca Merge pull request #23 from file-tunnel/dependabot/github_actions/cachix/install-nix-action-31.11.1
68d67b0 Merge pull request #25 from file-tunnel/agent/den-1176-mobile-sdk-parity
df31270 Merge pull request #26 from file-tunnel/dependabot/cargo/clients/rust/uuid-1.25.0
729a130 Merge pull request #27 from file-tunnel/dependabot/nix/nixpkgs-2c423e0
4d0bcb7 Merge pull request #30 from file-tunnel/agent/fp-pass-3
f9086ab Build event socket URLs without mutating the HTTP base.
536f360 Merge pull request #29 from file-tunnel/agent/den-3585-client-contract-20260827

## head (automation/nightly-client-hardening) last 8 commits
a821a48 feat: harden canonical polyglot client contract
dfd339f fix: validate the canonical 20-runtime client matrix
20b09cc Merge remote-tracking branch 'origin/automation/nightly-client-hardening'
28eb62b ci: pin client actions and add Java smoke gate
28bf681 Merge remote-tracking branch 'origin/main'
d0d895d fix: restore client hardening checks
f0935bf feat: harden canonical polyglot client contract
6ae3500 Merge pull request #19 from file-tunnel/dependabot/github_actions/actions/checkout-7

## merge-base: dfd339f238932b7ed209b677916f9fcb8d249670

## PR diff stat (merge-base..head)
 clients/go/.zed-api-surface.sha256                 |   2 +-
 clients/go/.zed-client-contract.json               |   2 +-
 clients/java/.zed-api-surface.sha256               |   2 +-
 clients/java/.zed-client-contract.json             |   2 +-
 clients/kotlin/.zed-api-surface.sha256             |   2 +-
 clients/kotlin/.zed-client-contract.json           |   2 +-
 clients/php/.zed-api-surface.sha256                |   2 +-
 clients/php/.zed-client-contract.json              |   2 +-
 clients/python/.zed-api-surface.sha256             |   2 +-
 clients/python/.zed-client-contract.json           |   4 +-
 clients/ruby/.zed-api-surface.sha256               |   2 +-
 clients/ruby/.zed-client-contract.json             |   2 +-
 clients/rust/.zed-api-surface.sha256               |   2 +-
 clients/rust/.zed-client-contract.json             |   2 +-
 clients/sdk-matrix.json                            |  12 +-
 clients/swift/.zed-api-surface.sha256              |   2 +-
 clients/swift/.zed-client-contract.json            |   2 +-
 .../.zed-contracts/nodejs/.zed-api-surface.sha256  |   2 +-
 .../nodejs/.zed-client-contract.json               |   4 +-
 clients/typescript/bun/.zed-api-surface.sha256     |   2 +-
 clients/typescript/bun/.zed-client-contract.json   |   4 +-
 clients/typescript/deno/.zed-api-surface.sha256    |   2 +-
 clients/typescript/deno/.zed-client-contract.json  |   4 +-
 clients/typescript/edge/.zed-api-surface.sha256    |   2 +-
 clients/typescript/edge/.zed-client-contract.json  |   4 +-
 clients/wasm/.zed-api-surface.sha256               |   2 +-
 clients/wasm/.zed-client-contract.json             |   2 +-
 clients/zig/.zed-api-surface.sha256                |   2 +-
 clients/zig/.zed-client-contract.json              |   2 +-
 46 files changed, 387 insertions(+), 106 deletions(-)

## base diff stat (merge-base..base)
 clients/typescript/edge/.zed-client-contract.json  |    4 +-
 clients/typescript/src/index.ts                    |    9 +-
 clients/typescript/test/client.test.mjs            |   16 +
 clients/wasm/.zed-api-surface.sha256               |    2 +-
 clients/wasm/.zed-client-contract.json             |    2 +-
 clients/zig/.zed-api-surface.sha256                |    2 +-
 clients/zig/.zed-client-contract.json              |    2 +-
 flake.lock                                         |    6 +-
 schemas/client-api.schema.json                     |  718 +++++++++
 scripts/check-validation-imports.py                |   11 +
 scripts/client_contract_boundary.py                |  123 ++
 scripts/harden_client_contract.py                  | 1573 ++++++++++++++++++++
 scripts/validate-zed-package.py                    |   14 +-
 scripts/validate_client_matrix.py                  |   90 +-
 scripts/verify_client_contract.py                  |  279 ++++
 tests/test_client_contract_boundary.py             |   50 +
 validation-consumer/README.md                      |    5 +
 validation-consumer/gleam/gleam.toml               |    9 +
 .../gleam/src/ftnl_validation_consumer.gleam       |    4 +
 .../gleam/test/ftnl_validation_consumer_test.gleam |   15 +
 validation-consumer/golang/consumer.go             |   12 +
 validation-consumer/golang/consumer_test.go        |   11 +
 validation-consumer/golang/go.mod                  |    7 +
 validation-consumer/rust/Cargo.toml                |   13 +
 validation-consumer/rust/src/lib.rs                |   23 +
 validation-consumer/typescript/package.json        |    9 +
 validation-consumer/typescript/src/index.ts        |   14 +
 .../typescript/test/consumer.test.ts               |   11 +
 validation-consumer/typescript/tsconfig.json       |   15 +
 90 files changed, 5583 insertions(+), 220 deletions(-)

## merge output
Auto-merging .zpkg.toml
CONFLICT (content): Merge conflict in .zpkg.toml
Auto-merging clients/.api-surface.sha256
CONFLICT (content): Merge conflict in clients/.api-surface.sha256
Auto-merging clients/api-surface.json
Auto-merging clients/c/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/c/.zed-api-surface.sha256
Auto-merging clients/c/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/c/.zed-client-contract.json
Auto-merging clients/client-api.schema.json
Auto-merging clients/contract-manifest.json
CONFLICT (content): Merge conflict in clients/contract-manifest.json
Auto-merging clients/cpp/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/cpp/.zed-api-surface.sha256
Auto-merging clients/cpp/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/cpp/.zed-client-contract.json
Auto-merging clients/dart/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/dart/.zed-api-surface.sha256
Auto-merging clients/dart/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/dart/.zed-client-contract.json
Auto-merging clients/elixir/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/elixir/.zed-api-surface.sha256
Auto-merging clients/elixir/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/elixir/.zed-client-contract.json
Auto-merging clients/erlang/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/erlang/.zed-api-surface.sha256
Auto-merging clients/erlang/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/erlang/.zed-client-contract.json
Auto-merging clients/gleam/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/gleam/.zed-api-surface.sha256
Auto-merging clients/gleam/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/gleam/.zed-client-contract.json
Auto-merging clients/go/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/go/.zed-api-surface.sha256
Auto-merging clients/go/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/go/.zed-client-contract.json
Auto-merging clients/java/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/java/.zed-api-surface.sha256
Auto-merging clients/java/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/java/.zed-client-contract.json
Auto-merging clients/kotlin/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/kotlin/.zed-api-surface.sha256
Auto-merging clients/kotlin/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/kotlin/.zed-client-contract.json
Auto-merging clients/php/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/php/.zed-api-surface.sha256
Auto-merging clients/php/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/php/.zed-client-contract.json
Auto-merging clients/python/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/python/.zed-api-surface.sha256
Auto-merging clients/python/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/python/.zed-client-contract.json
Auto-merging clients/ruby/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/ruby/.zed-api-surface.sha256
Auto-merging clients/ruby/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/ruby/.zed-client-contract.json
Auto-merging clients/rust/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/rust/.zed-api-surface.sha256
Auto-merging clients/rust/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/rust/.zed-client-contract.json
Auto-merging clients/swift/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/swift/.zed-api-surface.sha256
Auto-merging clients/swift/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/swift/.zed-client-contract.json
Auto-merging clients/typescript/.zed-contracts/nodejs/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/typescript/.zed-contracts/nodejs/.zed-api-surface.sha256
Auto-merging clients/typescript/.zed-contracts/nodejs/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/typescript/.zed-contracts/nodejs/.zed-client-contract.json
Auto-merging clients/typescript/bun/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/typescript/bun/.zed-api-surface.sha256
Auto-merging clients/typescript/bun/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/typescript/bun/.zed-client-contract.json
Auto-merging clients/typescript/deno/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/typescript/deno/.zed-api-surface.sha256
Auto-merging clients/typescript/deno/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/typescript/deno/.zed-client-contract.json
Auto-merging clients/typescript/edge/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/typescript/edge/.zed-api-surface.sha256
Auto-merging clients/typescript/edge/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/typescript/edge/.zed-client-contract.json
Auto-merging clients/wasm/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/wasm/.zed-api-surface.sha256
Auto-merging clients/wasm/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/wasm/.zed-client-contract.json
Auto-merging clients/zig/.zed-api-surface.sha256
CONFLICT (content): Merge conflict in clients/zig/.zed-api-surface.sha256
Auto-merging clients/zig/.zed-client-contract.json
CONFLICT (content): Merge conflict in clients/zig/.zed-client-contract.json
Automatic merge failed; fix conflicts and then commit the result.
