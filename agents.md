# File Tunnel client agent instructions

These instructions apply to this repository and every directory beneath it.

## Skill routing

Load only the skill that matches the task:

- For adding an SDK to an application, read
  [`agents/skills/integrate-file-tunnel-client/SKILL.md`](agents/skills/integrate-file-tunnel-client/SKILL.md).
- For changing SDK behavior or preserving cross-language parity, read
  [`agents/skills/maintain-file-tunnel-clients/SKILL.md`](agents/skills/maintain-file-tunnel-clients/SKILL.md).

Treat each skill as additional instructions, not a replacement for this file.

## Security boundaries

- Treat the tunnel UUID as a routing identifier, never as authorization.
- Keep desktop and phone capabilities out of URLs, logs, telemetry, fixtures, and error messages.
- Keep the one-time pairing secret in the URI fragment and exchange it for a scoped phone capability.
- Use a freshly minted, one-time event ticket for WebSocket setup. Reconcile sequence gaps with a tunnel snapshot.
- Do not persist capabilities by default. If a host explicitly requires restart recovery, use its platform secure store and preserve expiry.
- Do not retry ambiguous mutations unless the operation has a stable idempotency key or a documented resumable-upload contract.

## Contract and validation

- Keep Rust, TypeScript, Dart, and Gleam behavior aligned with `ftnl-interfaces`.
- Preserve language-idiomatic APIs; wire names remain the canonical `snake_case` contract.
- Test the affected package while iterating, then run all four package suites before completing a cross-language change.
- Run `nix develop --command agent-check` before completing a change.
- Never commit credentials, generated build trees, package archives, or machine-specific state.

## Git workflow

- Work on `main` during repository bootstrap and commit focused, reviewable changes.
- Pull and merge remote work before pushing; avoid git rebase in favor of git merge.
- Never discard unrelated or uncommitted user work.

## Repository-local Git worktrees

- Create or use a Git worktree only when the human operator explicitly authorizes it for the current task. Concurrency or a dirty checkout is not permission by itself.
- Put every authorized worktree at `<repository-root>/tmp/worktrees/<name>`; from the repository root, use `./tmp/worktrees/<name>`. Never place worktrees beside repositories or organization directories.
- Keep `tmp`, `temp`, `tmp/worktrees`, and `temp/worktrees` ignored in the repository-root `.gitignore`. Do not commit files from those directories.
- Relocate or remove a worktree only when the operator explicitly requests it. Before removal, preserve and publish intended changes, verify its commit is represented on the target branch, and confirm there are no tracked, untracked, ignored-sensitive, or in-use files that must survive. Remove it with `git worktree remove <path>` without `--force`; never delete a worktree directory with `rm`.
