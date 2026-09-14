# Treeward pull verification

Two trials are recorded here. The first, on 2026-09-08, exercised the tooling against real releases without touching the
live tap. The second, on 2026-09-13, verified the candidate that activates treeward's migration: the first
pull-generated formula committed to `Formula/treeward.rb`, upgrading from the last formula the upstream publisher
pushed. Both established native runtime coverage on Linux x86-64 only; the Linux ARM64 and macOS archives were
downloaded and validated but not executed.

## Migration candidate, 2026-09-13

Upstream released [treeward v0.3.3](https://github.com/scode/treeward/releases/tag/v0.3.3) after its release workflow
stopped pushing a formula, so no `treeward.rb` was attached to the release and the tap formula stayed at v0.3.2. The
candidate was produced by `cargo xtask update treeward --tag v0.3.3` against the live `pull.toml`, which was empty and
gained its first entry. `regenerate --check` passed afterwards. The four recorded archive hashes matched the checksums
upstream published alongside the release (`sha256.sum` and the per-archive `.sha256` files); this is a consistency check
between two views of the same release, not independent evidence about the build.

| Formula                         | SHA-256                                                            |
| ------------------------------- | ------------------------------------------------------------------ |
| Candidate v0.3.3 (pull)         | `85c9c4c88181a707bdbf6f176c6854d994b4f07fe0f41a73989d64b68f9da5a0` |
| Previous v0.3.2 (upstream push) | `f472954814b6153410e0aa6b9ad23976999dc2143894fe21f07d4edba0678b7b` |

The upgrade baseline was deliberately the formula upstream had pushed, not a pull-generated v0.3.2, because that is what
existing installations actually have. The two formulas differ in structure (dist's generated Ruby versus the tap's
renderer) and the pushed one defines no `test` block. The acceptance script now skips `brew test` for a formula without
one and says so, rather than failing the trial; the first run of this trial failed at exactly that point.

The container environment was the same pinned image as the first trial (Ubuntu 24.04.4 LTS, glibc 2.39, Homebrew 6.0.22,
digest below). The v0.3.3 Linux x86-64 archive SHA-256 was
`b0246b228add03ff34804eb48f125ba9bd8dfc9df62e8bd9a34f6e3101e0d231`; its installed executable matched
`b2138387afeb30ece7bdceb910c98bd37ce5b0f97992f91d60bbbda8e43aff1f` after both fresh install and upgrade.

| Operation                                                              | Result |
| ---------------------------------------------------------------------- | ------ |
| Fresh v0.3.3 install, installed-byte identity, functional test         | Passed |
| Uninstall, then pushed v0.3.2 install, identity (no test block)        | Passed |
| `brew upgrade` from pushed v0.3.2 to v0.3.3, identity, functional test | Passed |

To repeat it, place the candidate formula at `new/treeward.rb` and the previously committed formula at `old/treeward.rb`
in the inputs directory together with the candidate's `pull.toml` as `new.toml`, then run the container recipe below
with `/inputs/new.toml` in place of the config argument and `0.3.2` as the baseline version.

## Tooling trial, 2026-09-08

Verified on 2026-09-08: the updater generated a candidate from real upstream releases, Homebrew installed treeward
v0.3.2, and upgrading from v0.3.1 to v0.3.2 passed. At that point the live `pull.toml` was empty; these were uncommitted
scratch formulas, and the existing `Formula/treeward.rb` and upstream publisher were not changed.

### Candidate identity

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

### Environment and results

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

### Repeat the trial

Use a checkout of the documented tooling commit to generate inputs. The acceptance script is the same one the `Formula
upgrade` workflow runs on pull requests; it takes the tool name, the candidate formula, the pull configuration that
records the candidate's tag and hashes, and optionally the baseline formula and its version. The two trials recorded
above ran an earlier treeward-specific script with the same install, identity, and upgrade steps; the shared script
reproduced the migration candidate's results on the same image before replacing it. The container recipe below pins the
Linux x86-64 environment the trials used, which the workflow's runner images do not.

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
to [the acceptance script](../scripts/formula-upgrade-test.sh), then run:

```bash
acceptance_script=/path/to/scripts/formula-upgrade-test.sh
uname -m || exit 1
docker run --rm --network bridge \
  -e HOMEBREW_NO_AUTO_UPDATE=1 \
  -e HOMEBREW_NO_ANALYTICS=1 \
  -e HOMEBREW_NO_INSTALL_CLEANUP=1 \
  --mount "type=bind,src=$trial,dst=/inputs,readonly" \
  --mount "type=bind,src=$acceptance_script,dst=/acceptance.sh,readonly" \
  ghcr.io/homebrew/ubuntu24.04@sha256:613f2f524c4d1fb8fe37dbe7a5581392c89e7865bac725bab0d8e24309ae6d7c \
  bash /acceptance.sh treeward /inputs/new/treeward.rb /inputs/new.toml /inputs/old/treeward.rb 0.3.1
```

The script prints the environment, installed versions, executable digests, formula tests, and a final PASS marker. It
must exit 0. The container is removed afterward. Do not substitute a host tap or host Homebrew installation for the
disposable container without adapting the procedure to preserve existing state.

The trial initially caught Homebrew's refusal to overwrite a file through `Pathname#write`; the corrected formula uses
`File.write` for the negative-test fixture. It also showed that the Docker Hub `homebrew/brew:latest` image was older
than the Ubuntu image used here. Inspect and pin the actual environment instead of treating `latest` as evidence of
freshness. This Ubuntu/glibc result does not establish compatibility with older Linux distributions.
