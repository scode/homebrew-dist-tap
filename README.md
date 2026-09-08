# homebrew-dist-tap

Homebrew formulas for tools published by scode. Install a tool with `brew install scode/dist-tap/<tool>`.

The tap supports preparing formula updates from explicitly selected upstream releases. Agents research releases and
maintain the packaging rules; a deterministic Rust xtask downloads the expected archives and records their hashes.
Upstream projects can use any build system.

The live pull configuration currently opts in no tools. Existing formulas are still published by their upstream
workflows. Treeward's updater and example configuration demonstrate the pull flow without activating its migration.

For updater commands and their contracts, read [SPEC.md](SPEC.md). For onboarding, release review, and testing an
unmerged candidate, read [the maintenance guide](docs/pull-workflow.md). The
[treeward verification report](docs/treeward-verification.md) records the platforms and releases actually tested.
