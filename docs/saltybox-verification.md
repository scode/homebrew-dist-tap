# Saltybox pull verification

Verified on 2026-09-14: the candidate that activates saltybox's migration, the first pull-generated
`Formula/saltybox.rb`, installed and upgraded from the last formula the upstream publisher pushed on native Linux
x86-64, Linux ARM64, and macOS ARM64. Intel macOS was not executed; its archive was downloaded and validated only.

## Candidate identity

Upstream released [saltybox v5.0.1](https://github.com/scode/saltybox/releases/tag/v5.0.1) after its release workflow
stopped publishing a formula (`installers = []` in its dist configuration), so no `saltybox.rb` was attached to the
release and the tap formula stayed at v5.0.0. The candidate was produced by `cargo xtask update saltybox --tag v5.0.1`
against the live `pull.toml`, which gained its second entry; `regenerate --check` passed afterwards. The four recorded
archive hashes matched the checksums upstream published alongside the release (`sha256.sum` and the per-archive
`.sha256` files); this is a consistency check between two views of the same release, not independent evidence about the
build. [The example config](../examples/saltybox.toml) records the same values.

| Formula                         | SHA-256                                                            |
| ------------------------------- | ------------------------------------------------------------------ |
| Candidate v5.0.1 (pull)         | `fd7fd352575f48ff41115161c25c17e66bbbda029e9fd823bf43fc22ce4b573f` |
| Previous v5.0.0 (upstream push) | `27fc89ef9ddb7645126577f094108eb8248560f6456318913f684580bfe4893f` |

The candidate formula is committed in the migration pull request, so its digest identifies the reviewed bytes. Its test
block encrypts a file with a passphrase supplied through `--passphrase-stdin`, decrypts it and compares the plaintext,
then requires a decrypt with a wrong passphrase to exit 1 with `failed to decrypt` and leave no output file. The CLI's
behaviour under `--passphrase-stdin` and its wrong-passphrase exit status were first checked by running the extracted
Linux x86-64 binary in a network-less container; no upstream code ran on the workstation.

## Results

The pinned Linux x86-64 container (the image and digest recorded in
[the treeward report](treeward-verification.md#environment-and-results)) ran `scripts/formula-upgrade-test.sh` with the
candidate, the live `pull.toml`, and the pushed v5.0.0 formula as the upgrade baseline. The v5.0.1 executable matched
`1b214513696f7d986579edc306b37ecfcbaa97af0bf6742c47f4dcff7d5b4b14` after both fresh install and upgrade; the v5.0.0
executable matched `bd5fe3246fbd39a8dba270673a0d306df720dd32076a89df4c45455272f2fc75`. The pushed baseline defines no
test block, so `brew test` was skipped for it and required for the candidate.

The migration pull request's `Formula upgrade` workflow then ran the same script on GitHub's native runners
([run 34798172639](https://github.com/scode/homebrew-dist-tap/actions/runs/34798172639)):

| Platform     | Fresh v5.0.1, hash vs `pull.toml`, `brew test` | Pushed v5.0.0 install, identity | `brew upgrade` to v5.0.1, identity, `brew test` |
| ------------ | ---------------------------------------------- | ------------------------------- | ----------------------------------------------- |
| Linux x86-64 | Passed                                         | Passed                          | Passed                                          |
| Linux ARM64  | Passed                                         | Passed                          | Passed                                          |
| macOS ARM64  | Passed                                         | Passed                          | Passed                                          |

Runner images track current Homebrew and OS versions and are not a pinned baseline; the container run above is the
reproducible one. To repeat it, generate the candidate from the example config into a scratch directory, take the
baseline from `git show <main-before-migration>:Formula/saltybox.rb`, and follow the container recipe in the treeward
report with `saltybox`, the candidate formula, the example config, the baseline formula, and `5.0.0` as arguments.
