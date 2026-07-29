# shellcheck shell=bash
set -euo pipefail

(
  cd clients/rust
  cargo fmt --check
  cargo clippy --locked --all-targets -- -D warnings
  cargo test --locked --all-targets
)

(
  cd clients/typescript
  npm ci
  npm test
)

(
  cd clients/dart
  dart pub get
  dart format --output=none --set-exit-if-changed .
  dart analyze
  dart test
)

(
  cd clients/gleam
  gleam format --check src test
  gleam deps download
  gleam test
)

python3 scripts/validate-zed-package.py --manifest-only
