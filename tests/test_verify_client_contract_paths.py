"""Adversarial source-evidence checks for the canonical SDK manifest."""
from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import verify_client_contract as verifier


class ImplementationEvidenceTests(unittest.TestCase):
    def test_plain_sources_remain_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "sdk"
            target.mkdir()
            (target / "index.ts").write_text("export const ok = true;\n", encoding="utf-8")
            (target / "package.json").write_text('{"name":"sdk"}\n', encoding="utf-8")
            count, checksum = verifier.implementation_evidence(target)
            self.assertEqual(count, 2)
            self.assertEqual(len(checksum), 64)
            self.assertEqual((count, checksum), verifier.implementation_evidence(target))

    def test_source_symlink_cannot_hash_external_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "sdk"
            target.mkdir()
            (target / "index.ts").write_text("export const ok = true;\n", encoding="utf-8")
            external = root / "private.ts"
            external.write_text("do not admit this byte stream\n", encoding="utf-8")
            (target / "alias.ts").symlink_to(external)
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit):
                verifier.implementation_evidence(target)
            self.assertIn("must not be a symlink", stderr.getvalue())
            self.assertNotIn("do not admit this byte stream", stderr.getvalue())

    def test_target_directory_symlink_is_denied(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "sdk"
            target.mkdir()
            (target / "index.ts").write_text("export const ok = true;\n", encoding="utf-8")
            alias = root / "alias"
            alias.symlink_to(target, target_is_directory=True)
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit):
                verifier.implementation_evidence(alias)
            self.assertIn("target directory must not be a symlink", stderr.getvalue())

    def test_manifest_target_symlink_is_rejected_before_resolve(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            clients = root / "clients"
            clients.mkdir()
            actual = clients / "sdk"
            actual.mkdir()
            (clients / "alias").symlink_to(actual, target_is_directory=True)
            stderr = io.StringIO()
            with mock.patch.object(verifier, "ROOT", root):
                with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit):
                    verifier.resolve_inside(clients, "clients/alias", "target test")
            self.assertIn("contains a symlink", stderr.getvalue())

    def test_manifest_path_cannot_traverse_parent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            clients = root / "clients"
            clients.mkdir()
            with mock.patch.object(verifier, "ROOT", root):
                with self.assertRaises(SystemExit):
                    verifier.resolve_inside(clients, "clients/../clients", "target test")

    def test_ignored_dependency_tree_does_not_pollute_fingerprint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "sdk"
            ignored = target / "node_modules"
            ignored.mkdir(parents=True)
            (target / "index.ts").write_text("export const ok = true;\n", encoding="utf-8")
            external = root / "outside.ts"
            external.write_text("not a tracked SDK source\n", encoding="utf-8")
            (ignored / "alias.ts").symlink_to(external)
            count, _ = verifier.implementation_evidence(target)
            self.assertEqual(count, 1)


if __name__ == "__main__":
    unittest.main()
