# Treeward pull verification

Verified on 2026-09-08: the updater generated a candidate from real upstream releases, Homebrew installed treeward
v0.3.2, and upgrading from v0.3.1 to v0.3.2 passed. Native runtime coverage is Linux x86-64 only. The four platform
archives were downloaded and validated; Linux ARM64 and both macOS binaries were not executed.

The live `pull.toml` remains empty. These were uncommitted scratch formulas; the existing `Formula/treeward.rb` and
upstream publisher were not changed. This report records a tooling trial, not an activated migration.

## Candidate identity

Tooling commit: `83da74bb7f9aed556bfd963e6432f38ef51e186f`. The tested source tree is identical to this commit, and
regeneration from the committed tooling reproduced the formula digest below. The formula itself was scratch output, so
the tooling commit alone does not identify it.

| Generated formula | SHA-256                                                            |
| ----------------- | ------------------------------------------------------------------ |
| v0.3.2            | `5a643b0682c311d53b007cc45401170f7e094fc928f3bf7150929cc691267099` |
| v0.3.1            | `65c185f11719514a21865ef8679db8a9e2736255fb31e93a2ffffd0415477501` |

The selected upstream release is [treeward v0.3.2](https://github.com/scode/treeward/releases/tag/v0.3.2).
[The example config](../examples/treeward.toml) records all four archive hashes and exactly matched the config produced
by explicit update. The older [v0.3.1 release](https://github.com/scode/treeward/releases/tag/v0.3.1) supplied the
upgrade baseline. Its Linux x86-64 archive SHA-256 was
`47a18e2e43734fc0915338e32646e856ab799c964f72bebf35a7b4bf215641b4`; the v0.3.2 Linux x86-64 archive was
`6f99269a5455fe479e776d46ef2ce3b1b70ab6c5a36456ae4e7815ef178b55cd`.

## Environment and results

The disposable container ran as the ordinary `linuxbrew` image user at Homebrew's supported prefix. No host home
directory, publishing credentials, or writable repository was mounted. Inputs were the generated formulas and the
acceptance script, mounted read-only. Automatic Homebrew updates and analytics were disabled.

| Component           | Observed value                                                            |
| ------------------- | ------------------------------------------------------------------------- |
| Native architecture | x86_64                                                                    |
| OS                  | Ubuntu 24.04.4 LTS                                                        |
| glibc               | 2.39                                                                      |
| Homebrew            | 6.0.22                                                                    |
| Image               | `ghcr.io/homebrew/ubuntu24.04`                                            |
| Image digest        | `sha256:613f2f524c4d1fb8fe37dbe7a5581392c89e7865bac725bab0d8e24309ae6d7c` |

Homebrew fetched the formula's Linux archive and checked its recorded checksum. It also installed its `xz` extraction
dependency. Each installation passed `brew test`: initialize checksums, verify unchanged content, change a file, then
require verification to exit 1 with `Verification failed`.

| Operation                                                       | Result |
| --------------------------------------------------------------- | ------ |
| Fresh v0.3.2 install, installed-byte identity, functional test  | Passed |
| Uninstall, then v0.3.1 install, identity, functional test       | Passed |
| `brew upgrade` from v0.3.1 to v0.3.2, identity, functional test | Passed |

These treeward releases do not implement `--version`. Identity was established through Homebrew's installed version and
resolved prefix, then by comparing the installed executable's SHA-256 with the executable extracted from the cached,
checksum-verified archive. The v0.3.2 executable matched
`7cb0e1b32b583f61c43dc89ea38a7a6c6243c9a28fc2645e3c5d783ee53f605b` after both fresh install and upgrade; v0.3.1 matched
`08855daceb0ff9fa988dd5cb3ed6fd097b64319805a2923ba320d8a99869770a`.

Real-asset updater checks also passed: explicit selection of both tags, regeneration, a successful consistency check,
and a repeated current update preserving config/formula inode and modification time. Adding a deliberate formula comment
made `regenerate --check` exit 1 without changing either file. Regeneration removed that drift and reproduced the
recorded formula digest. Replacing a recorded hash with 64 zeroes made regeneration fail with a hash-mismatch diagnostic
before creating its output directory. Routine CI covers failure contracts with local fixtures rather than depending on
these mutable upstream URLs.

## Repeat the trial

Use a checkout of the documented tooling commit to generate inputs. Obtain the acceptance script from this report's
revision: it is the same script used for the trial and intentionally fixes these two treeward releases and Linux x86-64.
It is an example for reproducing this observation, not a general platform runner. For other tools or candidates, use the
parameterized recipe in [the maintenance guide](pull-workflow.md).

From the tooling checkout, use an empty scratch directory outside the tap:

```bash
trial=/path/to/empty-trial
mkdir -p "$trial" || exit 1
cp pull.toml "$trial/new.toml" || exit 1
cp pull.toml "$trial/old.toml" || exit 1
cargo xtask --config "$trial/new.toml" --output-dir "$trial/new" update treeward --tag v0.3.2 || exit 1
cargo xtask --config "$trial/old.toml" --output-dir "$trial/old" update treeward --tag v0.3.1 || exit 1
cargo xtask --config "$trial/new.toml" --output-dir "$trial/new" regenerate --check || exit 1
sha256sum "$trial/new/treeward.rb" "$trial/old/treeward.rb" || exit 1
```

Compare those formula digests with the table above. On a native Linux x86-64 host with Docker, supply the absolute path
to [the acceptance script](../examples/test-treeward-linux.sh), then run:

```bash
acceptance_script=/path/to/test-treeward-linux.sh
uname -m || exit 1
docker run --rm --network bridge \
  -e HOMEBREW_NO_AUTO_UPDATE=1 \
  -e HOMEBREW_NO_ANALYTICS=1 \
  -e HOMEBREW_NO_INSTALL_CLEANUP=1 \
  --mount "type=bind,src=$trial,dst=/inputs,readonly" \
  --mount "type=bind,src=$acceptance_script,dst=/acceptance.sh,readonly" \
  ghcr.io/homebrew/ubuntu24.04@sha256:613f2f524c4d1fb8fe37dbe7a5581392c89e7865bac725bab0d8e24309ae6d7c \
  bash /acceptance.sh /inputs
```

The script prints the environment, installed versions, executable digests, formula tests, and a final PASS marker. It
must exit 0. The container is removed afterward. Do not substitute a host tap or host Homebrew installation for the
disposable container without adapting the procedure to preserve existing state.

The trial initially caught Homebrew's refusal to overwrite a file through `Pathname#write`; the corrected formula uses
`File.write` for the negative-test fixture. It also showed that the Docker Hub `homebrew/brew:latest` image was older
than the Ubuntu image used here. Inspect and pin the actual environment instead of treating `latest` as evidence of
freshness. This Ubuntu/glibc result does not establish compatibility with older Linux distributions.
