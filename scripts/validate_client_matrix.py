#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SDK_MATRIX = json.loads((ROOT / "clients/sdk-matrix.json").read_text(encoding="utf-8"))
REQUIRED = {
    section["zed_target"]: section["dir"]
    for section in SDK_MATRIX["targets"].values()
}
EXPECTED_ADAPTERS = {
    "c": "none",
    "cpp": "none",
    "dart": "dart",
    "elixir": "none",
    "erlang": "none",
    "gleamlang": "none",
    "golang": "go",
    "java": "java",
    "kotlin": "java",
    "php": "none",
    "python3": "none",
    "ruby": "none",
    "rust": "rust",
    "rust-wasm": "rust",
    "swift": "none",
    "typescript-bun": "node",
    "typescript-deno": "none",
    "typescript-edge": "none",
    "typescript-nodejs": "node",
    "zig": "none",
}
ALLOWED_ADAPTERS = {"dart", "go", "java", "node", "none", "rust"}
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
expected_targets = {"repository", *REQUIRED}
if set(targets) != expected_targets:
    missing = sorted(expected_targets.difference(targets))
    extras = sorted(set(targets).difference(expected_targets))
    fail(f"Zed target drift: missing={missing}, extras={extras}")
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
if (ROOT / ".zpkg.lock").read_text(encoding="utf-8").strip() != "version = 1":
    fail(".zpkg.lock must contain exactly 'version = 1'")
print("client-matrix: ok")
