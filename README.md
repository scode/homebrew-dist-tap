# homebrew-dist-tap

Homebrew formulas for tools published by scode. Install a tool with `brew install scode/dist-tap/<tool>`.

The tap supports preparing formula updates from explicitly selected upstream releases. Agents research releases and
maintain the packaging rules; a deterministic Rust xtask downloads the expected archives and records their hashes.
Upstream projects can use any build system.

The live pull configuration is an opt-in list. Treeward, saltybox, and juggler are pull-managed: their formulas are
generated here from an explicitly selected release and reviewed before merge. Leiter is still published by its upstream
workflow until it is migrated.

For updater commands and their contracts, read [SPEC.md](SPEC.md). For onboarding, release review, and testing an
unmerged candidate, read [the maintenance guide](docs/pull-workflow.md). The verification reports for
[treeward](docs/treeward-verification.md), [saltybox](docs/saltybox-verification.md), and
[juggler](docs/juggler-verification.md) record the platforms and releases actually tested.
