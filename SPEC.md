# Pull updater specification

This tool does not discover releases, compare versions, run upstream code, or perform Git or GitHub operations. An agent
selects and reviews an explicit release. The deterministic Rust command downloads that release, validates its fixed
artifact contract, and keeps the selected hashes and generated Homebrew formula consistent.

## Commands

Run the tool through Cargo:

```console
cargo xtask [--config PATH] [--output-dir PATH] [--verbose] update TOOL --tag TAG [--dry-run]
cargo xtask [--config PATH] [--output-dir PATH] [--verbose] regenerate [--check]
```

The three global options may appear before or after the subcommand. `--config` defaults to `pull.toml` relative to the
invocation directory. The default output directory is `Formula` beside the resolved configuration path. An explicit
`--output-dir` is relative to the invocation directory. `--verbose` adds download details to diagnostics.

`update` supports `treeward` and requires an explicit safe `v`-prefixed SemVer tag. It accepts prerelease and build
syntax, including `v1.2.3-rc.1+build.4`, but rejects slashes, whitespace, quotes, and other characters outside ASCII
letters, digits, `.`, `-`, and `+`. Historical tags are allowed for reproduction. The agent running a live update must
review version direction because the tool does not prevent downgrades.

`regenerate` uses only tags and hashes already in the configuration. `--check` compares the validated generated formula
with disk and returns a runtime failure when it is missing or different. It never writes.

Examples:

```console
cargo xtask --config scratch/pull.toml --output-dir scratch/Formula update treeward --tag v0.3.2
cargo xtask --config examples/treeward.toml --output-dir scratch/Formula regenerate
cargo xtask --config examples/treeward.toml --output-dir scratch/Formula regenerate --check
cargo xtask update treeward --tag v0.3.2 --dry-run
```

## Configuration

The configuration must exist, contain UTF-8, and be a regular file reached without symlinks. Version 1 denies unknown
fields and has this shape:

```toml
schema_version = 1

[tools.treeward]
tag = "v0.3.2"

[tools.treeward.sha256]
aarch64-apple-darwin = "64 lowercase hexadecimal characters"
aarch64-unknown-linux-gnu = "64 lowercase hexadecimal characters"
x86_64-apple-darwin = "64 lowercase hexadecimal characters"
x86_64-unknown-linux-gnu = "64 lowercase hexadecimal characters"
```

`tools` is a map sorted by tool name. Each registered tool must contain exactly the supported target keys; missing and
extra targets fail. Unknown tools, schema versions, tool fields, and uppercase or otherwise malformed digests fail. An
empty `[tools]` table is valid and makes either regeneration mode return without network access or output-path activity.

`update` downloads and validates all four target archives. A different tag replaces only the selected tool's tag and
hash map. An update to the recorded tag still downloads every archive and requires every calculated hash to match;
changed bytes at one tag are an integrity error. `regenerate` also requires all downloaded bytes to match their recorded
hashes. A partial release never changes an output.

## Treeward archive contract

For tag `<tag>` and Rust target `<target>`, the only permitted URL is:

```text
https://github.com/scode/treeward/releases/download/<tag>/treeward-<target>.tar.xz
```

The initial request must use GitHub HTTPS. Redirects may follow release delivery to other HTTPS hosts, but an HTTP
downgrade is rejected. At most five redirects are followed. Connect timeout is 15 seconds and the whole request timeout
is 120 seconds. Response bodies are read through a 64 MiB cap. The client supplies no credentials, arbitrary URL option,
release enumeration, or persistent cache.

Every response must be one complete xz stream with a decoder-memory limit of 256 MiB. The entire expanded stream is
limited to 256 MiB. A corrupt or truncated xz trailer, second compressed stream, or compressed trailing junk fails. The
expanded tar must have at most 1024 entries and contain exactly:

```text
treeward-<target>/
treeward-<target>/README.md
treeward-<target>/CHANGELOG.md
treeward-<target>/LICENSE
treeward-<target>/treeward
```

The directory must be a directory entry. Its four children must be regular files, and `treeward` must have at least one
executable bit. Absolute paths, parent traversal, non-UTF-8 paths, duplicates, links, special files, missing or
unexpected entries, and data sizes that cannot be consumed all fail. Tar must have a complete two-block end marker. Only
bounded zero padding is accepted after the first end block; any nonzero trailing expanded data or hidden second tar
payload fails.

GNU and PAX extension headers are unexpected entries and are rejected, including headers that an ordinary tar reader
would consume as metadata for a later file. Archive validation does not extract or execute content. SHA-256 covers the
original compressed bytes.

## Outputs and failure behavior

The formula path is `<output-dir>/<tool>.rb`. Generated TOML and Ruby use stable sorted input and contain no timestamps.
The treeward formula selects the four supported platform and architecture combinations explicitly, installs only
`treeward`, `README.md`, `CHANGELOG.md`, and `LICENSE`, and tests a successful verification followed by the observed
`Verification failed` result after content changes.

Before network access, the tool validates all destinations it may use. Existing output directories must be directories,
and existing formula destinations must be regular UTF-8 files. Every existing destination path component must be
readable as metadata and must not be a symlink, even when followed by `..` in the supplied path. After those checks,
paths are normalized lexically for comparison and writing. Lexically equivalent configuration and formula paths collide
and fail, as do duplicate formula destinations. Missing output directories are allowed for a writing operation and are
created only after all downloads and archive validation pass. New formula files use mode `0644` on Unix; replacement
files preserve their existing mode.

`--dry-run` performs the same download, hash, archive, schema, and path checks as `update`, then reports only paths
whose bytes would change. It creates no directory or temporary file. `--check` behaves the same way for regeneration,
reports formula drift, and writes nothing. Permission errors and invalid UTF-8 in an existing destination are errors
rather than drift. Repeating a current update or regeneration performs its integrity checks but does not replace
byte-identical files, preserving their modification times.

A writing operation stages every changed output in a unique create-new temporary file beside its destination before
publishing any of them. Staging failures remove owned temporary files and leave destinations unchanged. If a later
rename fails, earlier renamed outputs are restored from staged backups. The original publication error, rollback errors,
and cleanup errors are reported together. Existing unrelated formulas are never read or changed.

These guarantees cover ordinary errors with one trusted local writer on a normally behaving local filesystem. They do
not provide a crash-atomic transaction across configuration and formula files, durable directory-entry commits, or
protection against a hostile process changing path components between validation and rename. A crash or failed rollback
can leave the pair inconsistent; inspect the reported paths and rerun `regenerate` after restoring a valid
configuration. Cleanup removes newly created output directories only when they remain empty.

Diagnostics go to stderr without timestamps. Normal operation writes nothing to stdout; Clap help and version output use
stdout. Success, help, and version exit 0. Clap syntax errors exit 2. Configuration, destination, network, hash,
archive, publication, cleanup, and check-drift errors exit 1 with the failing context.
