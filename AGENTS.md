# Agent instructions

This project is either public now, or may become public in the future. No content in this project should contain
personal information such as personal usernames, hostnames, details about the local environments, etc.

Public repository names and release URLs are necessary project metadata. Keep execution-host details and local paths out
of committed reports.

## Packaging constraints

An agent selects releases and researches packaging changes. The xtask operates on explicit inputs; never add automatic
release selection or let generated metadata execute upstream code. SPEC.md defines its user-visible contract. Update the
specification and meaningful tests with behavior changes.

The live pull.toml is an opt-in list. Tools absent from it remain push-managed. Never modify an unrelated formula or
disable an upstream publisher as a side effect of onboarding. Coordinate the publisher switch with the owner when an
actual migration is requested. An example configuration demonstrates behavior without opting a tool into live updates.

Prefer straightforward per-tool Rust code. Extract shared helpers for actual repetition or testability, not a generic
packaging framework. Keep upstream build choices independent of this tap.

Tests must not modify environment variables in their own process. Inject paths, fetchers, and other dependencies.
Routine tests use local fixtures; real release downloads and Homebrew installations are separate acceptance checks.

Docstrings and comments explain contracts, invariants, and intent that future readers cannot infer from syntax. After
code changes, make a separate documentation pass over every touched file, including private helpers and tests.

## Finish checks

Run the same commands as the dedicated CI jobs:

- `cargo fmt --all -- --check`
- `cargo clippy --locked --workspace --all-targets --all-features -- -D warnings`
- `cargo test --locked --workspace --all-targets --all-features`
- `dprint check`

Use stable Rust. Install dprint separately. Updating formatter plugins requires checksum pins; verify a fresh download
after changing them. Exclude lore from Markdown formatting and linting.

The dprint CI action adds JSON output for GitHub annotations; the local command reports the same formatting failures in
plain text.

## Conventional Commits

All commit messages and PR titles must use Conventional Commit format: `<type>: <short summary>`.

Allowed types: `feat`, `fix`, `docs`, `perf`, `refactor`, `style`, `test`, `chore`, `ci`, `revert`.

Append `!` after the type for breaking changes. Scope is optional. Choose the type by the user-visible effect: a bug fix
requiring refactoring is `fix`, and a new CLI flag is `feat`. The summary is lowercase, imperative, has no trailing
period, and keeps the first line under 72 characters.

## Lore

The ./lore directory contains historical information about the project. Only use it for historical digging or when
requested. Current project behavior does not use or depend on it, and routine maintenance does not touch it.
