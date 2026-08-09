# File Tunnel client matrix

Every SDK slice consumes the contracts published by `file-tunnel/ftnl-interfaces`. The organization does not currently publish an `ftnl-lib` package, so this manifest deliberately imports interfaces only.

Canonical Zed targets are `nodejs`, `python`, `golang`, `rust`, `dart`, `gleam`, `erlang`, `elixir`, `java`, `kotlin`, `ruby`, `php`, and `swift`.

Node.js, Deno, Bun, and edge entry points live inside `clients/typescript/runtimes/` instead of becoming noncanonical Zed targets.
