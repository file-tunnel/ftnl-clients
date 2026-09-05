#!/usr/bin/env python3
from __future__ import annotations

import json
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
EXPECTED_ADAPTERS = {
    "nodejs": "node",
    "python": "none",
    "golang": "none",
    "rust": "none",
    "dart": "none",
    "gleam": "none",
    "erlang": "none",
    "elixir": "none",
    "java": "java",
    "kotlin": "java",
    "ruby": "none",
    "php": "none",
    "swift": "none",
}
ALLOWED_ADAPTERS = {"node", "java", "none"}
FORBIDDEN = {"typescript", "python3", "gleamlang", "deno", "bun", "edge"}
RUNTIMES = {"nodejs", "deno", "bun", "edge"}
CANONICAL_ZED_TARGETS = {
    "c": "c",
    "cpp": "cpp",
    "dart": "dart",
    "elixir": "elixir",
    "erlang": "erlang",
    "gleamlang": "gleam",
    "golang": "golang",
    "java": "java",
    "kotlin": "kotlin",
    "php": "php",
    "python3": "python",
    "ruby": "ruby",
    "rust": "rust",
    "swift": "swift",
    "typescript-bun": "nodejs",
    "typescript-deno": "nodejs",
    "typescript-edge": "nodejs",
    "typescript-nodejs": "nodejs",
    "wasm": "rust-wasm",
    "zig": "zig",
}


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
    section = targets.get(target, {})
    if section.get("dir") != relative:
        fail(f"target {target!r} must point to {relative!r}")
    if not (ROOT / relative).is_dir():
        fail(f"missing SDK directory: {relative}")
    adapter = section.get("adapter")
    if adapter not in ALLOWED_ADAPTERS:
        fail(f"target {target!r} uses unsupported adapter {adapter!r}")
    if adapter != EXPECTED_ADAPTERS[target]:
        fail(
            f"target {target!r} must use adapter "
            f"{EXPECTED_ADAPTERS[target]!r}, got {adapter!r}"
        )

runtime_root = ROOT / "clients/typescript/runtimes"
present = {path.name for path in runtime_root.iterdir() if path.is_dir()} if runtime_root.is_dir() else set()
if present != RUNTIMES:
    fail(f"TypeScript runtimes must be {sorted(RUNTIMES)}, got {sorted(present)}")
for runtime in ("deno", "bun", "edge"):
    if not (ROOT / "clients/typescript" / runtime).is_dir():
        fail(f"missing TypeScript runtime folder: clients/typescript/{runtime}")
if (ROOT / ".zpkg.lock").read_text(encoding="utf-8").strip() != "version = 1":
    fail(".zpkg.lock must contain exactly 'version = 1'")

sdk_matrix = json.loads((ROOT / "clients/sdk-matrix.json").read_text(encoding="utf-8"))
matrix_targets = sdk_matrix.get("targets", {})
if set(matrix_targets) != set(CANONICAL_ZED_TARGETS):
    fail(
        "sdk-matrix targets must be exactly "
        f"{sorted(CANONICAL_ZED_TARGETS)}, got {sorted(matrix_targets)}"
    )
for name, expected_zed_target in CANONICAL_ZED_TARGETS.items():
    zed_target = matrix_targets[name].get("zed_target")
    if zed_target != expected_zed_target:
        fail(f"sdk-matrix {name!r} must map to Zed target {expected_zed_target!r}")
    if zed_target in FORBIDDEN:
        fail(f"sdk-matrix maps {name!r} to noncanonical Zed target {zed_target!r}")

print("client-matrix: ok")
