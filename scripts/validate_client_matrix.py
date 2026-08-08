#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parents[1]
REQUIRED = {
    "nodejs": "clients/typescript",
    "python": "clients/python",
    "golang": "clients/go",
    "rust": "clients/rust",
    "dart": "clients/dart",
    "gleam": "clients/gleam",
    "erlang": "clients/erlang",
    "elixir": "clients/elixir",
    "java": "clients/java",
    "kotlin": "clients/kotlin",
    "ruby": "clients/ruby",
    "php": "clients/php",
    "swift": "clients/swift",
}
FORBIDDEN = {"typescript", "python3", "gleamlang", "deno", "bun", "edge"}
RUNTIMES = {"nodejs", "deno", "bun", "edge"}


def fail(message: str) -> None:
    print(f"client-matrix: {message}", file=sys.stderr)
    raise SystemExit(1)


with (ROOT / ".zpkg.toml").open("rb") as handle:
    manifest = tomllib.load(handle)

package = manifest.get("package", {})
if package.get("org") != "file-tunnel" or package.get("name") != "ftnl-clients":
    fail("unexpected package identity")
dependencies = manifest.get("dependencies", {})
if "file-tunnel/ftnl-interfaces" not in dependencies:
    fail("ftnl-interfaces dependency is required")
if "file-tunnel/ftnl-lib" in dependencies:
    fail("do not invent an ftnl-lib dependency before that repository exists")

targets = manifest.get("targets", {})
bad = FORBIDDEN.intersection(targets)
if bad:
    fail(f"noncanonical Zed targets present: {sorted(bad)}")
for target, relative in REQUIRED.items():
    if targets.get(target, {}).get("dir") != relative:
        fail(f"target {target!r} must point to {relative!r}")
    if not (ROOT / relative).is_dir():
        fail(f"missing SDK directory: {relative}")

runtime_root = ROOT / "clients/typescript/runtimes"
present = {path.name for path in runtime_root.iterdir() if path.is_dir()} if runtime_root.is_dir() else set()
if present != RUNTIMES:
    fail(f"TypeScript runtimes must be {sorted(RUNTIMES)}, got {sorted(present)}")
if (ROOT / ".zpkg.lock").read_text(encoding="utf-8").strip() != "version = 1":
    fail(".zpkg.lock must contain exactly 'version = 1'")
print("client-matrix: ok")
