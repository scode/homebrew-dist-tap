#!/usr/bin/env python3
"""Print, as a JSON list, the pull-managed tools a change affects, for the formula upgrade workflow.

A tool is listed when its formula file or its pull.toml entry differs between BASE_COMMIT and HEAD
and it is present in HEAD's pull.toml. Either kind of change needs the install test: a hand-edited
formula needs it as much as a regenerated one, and a config-only change must be checked against the
unchanged formula so that config and formula cannot drift apart unnoticed. Tools absent from
pull.toml are still published by upstream and have no baseline this repository owns.

A tool listed in pull.toml whose formula is missing at HEAD is an error, not a skip: that is a
broken tap state (the config claims to own a formula that does not exist), and reporting it as
"nothing to test" would let a deletion or rename merge green.

Usage: changed-pull-managed-tools.py BASE_COMMIT

Runs from any directory inside the repository; paths are resolved against the repository root.
"""

import json
import os
import subprocess
import sys
import tomllib


def git_output(*args: str, check: bool = True) -> str | None:
    """Run git and return its stdout.

    With check, a failure exits after git's own stderr has been shown, so a bad base commit is
    diagnosed by git rather than by a bare status code. Without it, failure returns None quietly:
    the callers use that for a file that legitimately may not exist at the base commit.
    """
    result = subprocess.run(
        ["git", *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=None if check else subprocess.DEVNULL,
        text=True,
    )
    if result.returncode != 0:
        if check:
            sys.exit(f"git {' '.join(args)} failed with status {result.returncode}")
        return None
    return result.stdout


def tools_in_config(text: bytes) -> dict:
    """The per-tool tables of a pull configuration, keyed by tool name."""
    return tomllib.loads(text.decode("utf-8")).get("tools", {})


def changed_tools(base: str) -> list[str]:
    """Sorted tool names needing the install test between base and HEAD, relative to the repo root."""
    with open("pull.toml", "rb") as config_file:
        head_tools = tools_in_config(config_file.read())
    # The base may predate pull.toml entirely; every current entry then counts as changed.
    base_config = git_output("show", f"{base}:pull.toml", check=False)
    base_tools = tools_in_config(base_config.encode("utf-8")) if base_config is not None else {}

    missing = sorted(name for name in head_tools if not os.path.exists(os.path.join("Formula", f"{name}.rb")))
    if missing:
        sys.exit(f"pull.toml lists tools without a formula at HEAD: {', '.join(missing)}")

    changed = set()
    for path in git_output("diff", "--name-only", base, "HEAD", "--", "Formula").split("\n"):
        directory, name = os.path.split(path)
        if directory == "Formula" and name.endswith(".rb"):
            changed.add(name.removesuffix(".rb"))
    for name, entry in head_tools.items():
        if base_tools.get(name) != entry:
            changed.add(name)
    return sorted(changed & set(head_tools))


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} BASE_COMMIT", file=sys.stderr)
        return 2
    os.chdir(git_output("rev-parse", "--show-toplevel").strip())
    print(json.dumps(changed_tools(sys.argv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
