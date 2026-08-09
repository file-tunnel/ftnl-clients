#!/usr/bin/env python3
"""Validate the File Tunnel Zed package manifest and packed artifacts."""

from __future__ import annotations

import argparse
import io
import pathlib
import tarfile
import tomllib


NATIVE_MANIFESTS = {
    "nodejs": ("package.json",),
    "python": ("pyproject.toml",),
    "golang": ("go.mod",),
    "rust": ("Cargo.toml",),
    "dart": ("pubspec.yaml",),
    "gleam": ("gleam.toml",),
    "erlang": ("rebar.config",),
    "elixir": ("mix.exs",),
    "java": ("pom.xml",),
    "kotlin": ("build.gradle.kts",),
    "ruby": ("ftnl-client.gemspec",),
    "php": ("composer.json",),
    "swift": ("Package.swift",),
}


def read_toml(path: pathlib.Path) -> dict:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def validate_manifest(root: pathlib.Path) -> tuple[dict, dict]:
    manifest = read_toml(root / ".zpkg.toml")
    lock = read_toml(root / ".zpkg.lock")
    if lock.get("version") != 1:
        raise ValueError("unsupported .zpkg.lock version")

    package = manifest["package"]
    targets = manifest.get("targets", {})
    if targets.get("repository", {}).get("dir") != ".":
        raise ValueError("the repository target must package the repository root")

    required = {"repository", *NATIVE_MANIFESTS}
    missing = sorted(required.difference(targets))
    extras = sorted(set(targets).difference(required))
    if missing:
        raise ValueError(f"missing Zed targets: {', '.join(missing)}")
    if extras:
        raise ValueError(f"unexpected Zed targets: {', '.join(extras)}")

    for target, section in targets.items():
        source = root / section["dir"]
        if not source.is_dir():
            raise ValueError(f"{target} source directory does not exist: {section['dir']}")
        for filename in NATIVE_MANIFESTS.get(target, ()):
            if not (source / filename).is_file():
                raise ValueError(f"{target} is missing its native manifest: {filename}")

    expected_names = {
        section.get("name", f"{package['name']}-{target}")
        for target, section in targets.items()
    }
    if len(expected_names) != len(targets):
        raise ValueError("Zed target package names must be unique")

    return manifest, targets


def validate_artifacts(
    root: pathlib.Path,
    artifacts: pathlib.Path,
    manifest: dict,
    targets: dict,
) -> None:
    package = manifest["package"]
    expected: dict[str, pathlib.Path] = {}
    for target, section in targets.items():
        name = section.get("name", f"{package['name']}-{target}")
        expected[target] = (
            artifacts / f"{package['org']}-{name}-{package['version']}.tar.gz"
        )

    missing = [archive.name for archive in expected.values() if not archive.is_file()]
    if missing:
        raise ValueError(f"missing packed artifacts: {', '.join(missing)}")

    actual = set(artifacts.glob("*.tar.gz"))
    if actual != set(expected.values()):
        extras = sorted(path.name for path in actual.difference(expected.values()))
        raise ValueError(f"unexpected packed artifacts: {', '.join(extras)}")

    archive_members: dict[str, list[str]] = {}
    for target, archive in expected.items():
        with tarfile.open(archive, "r:gz") as packed:
            names = packed.getnames()
            if not names or not all(
                name == "pkg" or name.startswith("pkg/") for name in names
            ):
                raise ValueError(f"{target} artifact has entries outside pkg/")
            if any(".." in pathlib.PurePosixPath(name).parts for name in names):
                raise ValueError(f"{target} artifact contains path traversal")

            derived_member = packed.extractfile("pkg/.zpkg.toml")
            if derived_member is None:
                raise ValueError(f"{target} artifact has no derived .zpkg.toml")
            derived = tomllib.load(io.BytesIO(derived_member.read()))

        expected_name = targets[target].get("name", f"{package['name']}-{target}")
        if derived["package"]["name"] != expected_name:
            raise ValueError(f"{target} artifact has the wrong package name")
        if derived.get("targets"):
            raise ValueError(f"{target} artifact is still a polyglot package")
        archive_members[target] = names

    repository_files = archive_members["repository"]
    for target, section in targets.items():
        if target == "repository":
            continue

        source = root / section["dir"]
        native_paths = [source / name for name in NATIVE_MANIFESTS[target]]
        if not any(
            f"pkg/{path.relative_to(source).as_posix()}" in archive_members[target]
            for path in native_paths
        ):
            raise ValueError(f"{target} artifact omitted its native manifest")

        source_root = f"pkg/{section['dir'].strip('./')}"
        source_prefix = f"{source_root}/"
        if not any(
            name == source_root or name.startswith(source_prefix)
            for name in repository_files
        ):
            raise ValueError(f"repository artifact omitted the {target} source")
        if any(
            name == source_root or name.startswith(source_prefix)
            for name in archive_members[target]
        ):
            raise ValueError(f"{target} artifact was not re-rooted")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest-only",
        action="store_true",
        help="validate source metadata without requiring packed artifacts",
    )
    parser.add_argument(
        "--artifacts",
        type=pathlib.Path,
        help="directory containing tarballs emitted by zed-cli pack",
    )
    args = parser.parse_args()

    if not args.manifest_only and args.artifacts is None:
        parser.error("provide --manifest-only or --artifacts")

    root = pathlib.Path(__file__).resolve().parents[1]
    manifest, targets = validate_manifest(root)
    if args.artifacts is not None:
        validate_artifacts(root, args.artifacts.resolve(), manifest, targets)

    suffix = " and packed artifacts" if args.artifacts is not None else ""
    print(f"validated {len(targets)} Zed targets{suffix}")


if __name__ == "__main__":
    main()
