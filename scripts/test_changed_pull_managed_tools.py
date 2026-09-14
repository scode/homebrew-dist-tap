#!/usr/bin/env python3
"""Behavioral tests for changed-pull-managed-tools.py against throwaway git repositories.

These matter because the script decides whether the formula upgrade workflow runs at all: a false
"nothing changed" lets an untested formula merge, and a silent skip for a broken tap state hides a
deletion. Each test builds a small repository with a base commit and a HEAD commit and checks the
JSON the script prints, or that it exits non-zero. No test touches the process environment; the
script is run as a subprocess in the temporary repository's directory.

Run with `python3 -m unittest discover -s scripts`.
"""

import importlib.util
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("changed-pull-managed-tools.py")

TREEWARD_ENTRY = """
[tools.treeward]
tag = "v0.3.3"

[tools.treeward.sha256]
aarch64-apple-darwin = "{a}"
aarch64-unknown-linux-gnu = "{b}"
x86_64-apple-darwin = "{c}"
x86_64-unknown-linux-gnu = "{d}"
"""


def config(*, tools: str = "") -> str:
    """A pull.toml with the given tool tables, or an empty `[tools]` when none."""
    return "schema_version = 1\n" + (tools if tools else "\n[tools]\n")


def treeward_entry(marker: str = "0") -> str:
    """A treeward table whose hashes embed `marker`, so two entries can differ only in one hash."""
    return TREEWARD_ENTRY.format(a="a" * 64, b="b" * 64, c="c" * 64, d=marker * 64)


class Repo:
    """A temporary git repository with helpers to commit a tree and run the script."""

    def __init__(self, directory: str) -> None:
        self.path = pathlib.Path(directory)
        self.git("init", "--quiet")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "test")

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", *args], cwd=self.path, check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit(self, files: dict[str, str | None]) -> str:
        """Write (or delete, for None) the given files, commit, and return the commit hash."""
        for name, content in files.items():
            target = self.path / name
            if content is None:
                target.unlink()
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content)
        self.git("add", "-A")
        self.git("commit", "--quiet", "--allow-empty", "-m", "commit")
        return self.git("rev-parse", "HEAD")

    def run(self, base: str, cwd: str | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["python3", str(SCRIPT), base],
            cwd=cwd or self.path,
            check=False,
            capture_output=True,
            text=True,
        )


class ChangedPullManagedToolsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Repo(self.tmp.name)

    def assert_tools(self, base: str, expected: list[str], cwd: str | None = None) -> None:
        result = self.repo.run(base, cwd=cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), expected)

    def test_formula_change_of_pull_managed_tool_is_listed(self) -> None:
        """A changed formula for a tool in pull.toml needs the test even when the config is unchanged."""
        base = self.repo.commit({"pull.toml": config(tools=treeward_entry()), "Formula/treeward.rb": "v1"})
        self.repo.commit({"Formula/treeward.rb": "v2"})
        self.assert_tools(base, ["treeward"])

    def test_config_only_change_is_listed(self) -> None:
        """A hash change alone must test the unchanged formula so config and formula cannot drift apart."""
        base = self.repo.commit({"pull.toml": config(tools=treeward_entry("0")), "Formula/treeward.rb": "v1"})
        self.repo.commit({"pull.toml": config(tools=treeward_entry("1"))})
        self.assert_tools(base, ["treeward"])

    def test_push_managed_formula_change_is_ignored(self) -> None:
        """Formulas absent from pull.toml are upstream's; the workflow has no baseline it owns for them."""
        base = self.repo.commit({"pull.toml": config(), "Formula/other.rb": "v1"})
        self.repo.commit({"Formula/other.rb": "v2"})
        self.assert_tools(base, [])

    def test_no_change_yields_empty_list(self) -> None:
        base = self.repo.commit({"pull.toml": config(tools=treeward_entry()), "Formula/treeward.rb": "v1"})
        self.repo.commit({"README.md": "docs"})
        self.assert_tools(base, [])

    def test_base_without_config_counts_every_entry_as_changed(self) -> None:
        """First activation of the config has no prior entry to compare against, so every tool is new."""
        base = self.repo.commit({"Formula/treeward.rb": "v1"})
        self.repo.commit({"pull.toml": config(tools=treeward_entry())})
        self.assert_tools(base, ["treeward"])

    def test_missing_formula_for_listed_tool_fails(self) -> None:
        """A pull.toml entry whose formula was deleted or renamed is a broken tap, not a skip."""
        base = self.repo.commit({"pull.toml": config(tools=treeward_entry()), "Formula/treeward.rb": "v1"})
        self.repo.commit({"Formula/treeward.rb": None, "Formula/treeward2.rb": "v1"})
        result = self.repo.run(base)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("treeward", result.stderr)

    def test_runs_from_subdirectory(self) -> None:
        """The workflow runs from the root, but a maintainer may not; paths resolve against the repo root."""
        base = self.repo.commit({"pull.toml": config(tools=treeward_entry()), "Formula/treeward.rb": "v1"})
        self.repo.commit({"Formula/treeward.rb": "v2"})
        self.assert_tools(base, ["treeward"], cwd=str(self.repo.path / "Formula"))

    def test_unknown_base_fails(self) -> None:
        self.repo.commit({"pull.toml": config(), "Formula/treeward.rb": "v1"})
        result = self.repo.run("no-such-ref")
        self.assertNotEqual(result.returncode, 0)


class ScriptLoadsTest(unittest.TestCase):
    def test_script_is_importable_as_module(self) -> None:
        """Guards against syntax errors the subprocess tests would only report indirectly."""
        spec = importlib.util.spec_from_file_location("changed_pull_managed_tools", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertTrue(callable(module.changed_tools))


if __name__ == "__main__":
    unittest.main()
