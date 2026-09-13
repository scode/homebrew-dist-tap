# Maintain a formula from upstream releases

Use agents for release research and packaging changes. Use the Rust updater for an explicit, reviewed release input. The
builder upstream uses does not matter: dist, custom CI, and other builders are compatible when their release archives
meet the tool's documented contract.

The live pull.toml is an opt-in list. Treeward is the first activated migration: its upstream release workflow no longer
pushes a formula, and the live entry here owns `Formula/treeward.rb`. Other tools stay push-managed until their own
coordinated switch. Do not copy an example into live configuration without coordinating that switch.

## Why this migration exists

Upstream projects currently push formula updates into this tap, which requires giving their release workflows write
credentials here. The intended destination is to migrate every tool to pull updates: this repository consumes published
release artifacts, and a human reviews and merges the resulting formula change before it reaches the default branch.
Once all upstream publishers have migrated, their tap-write credentials can be removed. This reduces credential
management across projects and makes formula publication an explicit human decision.

Migration is deliberately per-tool. Push-managed and pull-managed formulas can coexist while each publisher is switched
over. The owner accepts that legacy publishers retain repository-wide write access during this period; the full security
and enforced review benefits depend on completing the migration and removing that access. This accepted transition is
not a reason to require a global conversion or block the first tool's migration.

The upstream build and release mechanism is a separate project decision. A tool can keep cargo-dist to build archives
and create releases, or replace it independently. Pulling here changes who publishes the Homebrew formula. The tap's
updater consumes the tool's documented archive contract without using dist or executing upstream-generated Ruby.

There are few tools, so agents research each tool's packaging, discover and select releases, maintain ordinary per-tool
Rust updaters, and help run acceptance checks and prepare reviewable changes. The deterministic xtask takes the explicit
release tag and records artifact hashes in the top-level config; that config and the updater determine the formula.
Recorded hashes bind the accepted bytes and detect replacement of an already recorded release. They do not establish
trust in the upstream build. Release discovery and judgment stay with the agent and owner, outside the updater.

Keep this maintenance model lightweight. A small amount of explicit per-tool code is practical at this scale; there is
no need for a generic packaging framework, template system, or automatic release-discovery service. Test candidate
formulas before merging, using isolated Homebrew installations and recording which platforms actually ran them.

## Onboard a tool

Inspect the upstream repository and a published release. Record the repository identity, exact tag, target set, archive
filenames, top-level directory layout, installed binaries, license, documentation, dependencies, and OS compatibility.
List archive contents before executing anything. Do not use an upstream installer or Ruby formula as metadata code.

Add ordinary per-tool Rust logic and a tested example config. Reuse helpers where their contracts fit; do not generalize
from imagined future tools. Add tests for malformed inputs and changes to the artifact contract as well as the expected
case. The supported target set belongs to the tool, not the workstation running its updater.

Every formula needs an installed-tool test that demonstrates useful behavior. A version check establishes identity; it
does not establish functionality. Treeward's example initializes checksums, verifies unchanged content, and rejects
modified content. Document any runtime dependencies the archive needs rather than relying on packages present on the
developer's machine.

Homebrew overrides `Pathname#write` to refuse overwriting an existing file. In a formula test that deliberately changes
a fixture, use `File.write(path, content)` for the replacement. The real treeward trial caught this after a successful
install and initial verification; Rust renderer tests cannot establish Homebrew API behavior.

Generate into a disposable checkout using an example config and explicit output directory. Review the complete formula
on first onboarding; later version updates should normally have a small diff. Preserve the live config and existing
formulas until installation checks have passed and migration is actually requested.

## Select and prepare a release

The agent finds releases in the upstream project's published releases page and checks the release notes. Select a
concrete stable tag unless the user explicitly wants another channel or a historical test. Compare it with the recorded
tag to catch an accidental downgrade. Verify all expected platform assets are present; a published release can still be
incomplete. The updater does not enumerate releases or decide what "latest" means.

Run the explicit update command described in SPEC.md, using dry-run first when inspecting a candidate. First selection
records the calculated hashes. Hashes establish which downloaded bytes the change accepts; they do not prove the
upstream build is trustworthy. If the same recorded release starts returning different bytes, stop and investigate. Do
not delete hashes or change tags merely to make an integrity error disappear.

Review the config and formula together. Look for the intended tag and four asset hashes in the treeward case, URLs under
the intended repository and release, preserved target coverage, and no unrelated file changes. Regenerate and check the
candidate to confirm that config and generated output agree. Commit and PR creation remain agent operations, outside the
deterministic tool. Coordinate a release update through the normal human review and merge process.

### Routine update checklist

A routine version bump of an already pull-managed tool is complete when all of these have been done and the PR states
the outcome of each. Skipping the install test because the diff "only changes hashes" is not acceptable: the hashes are
exactly what a broken or replaced archive would change, and the formula is what users run.

1. Run `update --dry-run`, then `update`, then `regenerate --check`.
2. Compare the recorded hashes with the checksums upstream published alongside the release, when it publishes any. This
   catches a bad download or a partial release; it does not vouch for the build.
3. Review the diff. Only the tool's tag, version, and hash lines should change. Anything else means the tool's archive
   contract or the updater changed and the change needs a wider review.
4. Let the `Formula upgrade` workflow run on the PR. For every pull-managed tool whose formula or `pull.toml` entry the
   PR changes, it installs the candidate, then installs the base branch's formula and upgrades from it, on native Linux
   x86-64, Linux ARM64, and macOS ARM64 runners. After each install it checks the keg version, compares the installed
   executable with the one inside the checksum-verified archive, and runs the formula's test; the candidate's archive is
   also compared with the hash recorded in `pull.toml`. Its `formula-upgrade` status must be green. It uses
   `scripts/formula-upgrade-test.sh`, which the container recipe in the verification report also uses; run that locally
   when a runner is unavailable or a failure needs a pinned environment to reproduce.
5. State in the PR which platforms actually ran the install test, including any the workflow could not cover.

The candidate's expected version and archive hash come from `pull.toml`, so a formula whose `url`, `sha256`, or
`version` points at a different release than the config records fails rather than verifying itself; a config-only change
is tested against the unchanged formula for the same reason. The baseline is only checked against its own archive, and
`brew test` is skipped for a baseline that defines no test block (a formula upstream pushed); the candidate must define
one. A change that keeps the same version cannot exercise `brew upgrade`, and the workflow says so instead of claiming
an upgrade. Runner images track current Homebrew and OS versions; they are not a pinned baseline. The verification
report is updated when a tool is onboarded or its migration is activated, not for every bump; the PR and its workflow
run carry the routine evidence.

## Test an unmerged candidate

A Homebrew tap is a Git checkout. An installed tap can use a branch or detached commit rather than the default branch;
Homebrew then reads that candidate formula. Use a disposable machine or isolated test tap, fetch the exact candidate
commit, and disable automatic updates during installation so it cannot switch inputs underneath the test.

For a formula committed in an unmerged candidate, run this in a disposable Homebrew environment. Supply the checkout,
commit, and formula name being reviewed. The temporary tap receives only the committed formula, without repository
credentials or a remote that can update it:

```bash
set -o pipefail
candidate_checkout=/path/to/candidate
candidate_ref='<full-commit-hash>'
formula_name='<tool>'
test_tap="$(brew --repository)/Library/Taps/local/homebrew-pull-test" || exit 1
test ! -e "$test_tap" || exit 1
mkdir -p "$test_tap" || exit 1
git -C "$candidate_checkout" archive "$candidate_ref" "Formula/$formula_name.rb" |
  tar -x -C "$test_tap" || exit 1
git -C "$test_tap" init --quiet || exit 1
HOMEBREW_NO_AUTO_UPDATE=1 brew install "local/pull-test/$formula_name" || exit 1
HOMEBREW_NO_AUTO_UPDATE=1 brew test "local/pull-test/$formula_name" || exit 1
```

For onboarding examples whose generated formula is deliberately uncommitted, generate into scratch from the pinned
tooling checkout and copy that reviewed output into the empty test tap instead of using `git archive`. Record the
formula's SHA-256 along with the tooling commit. The treeward verification report demonstrates this case.

Use the fully qualified test-tap formula name with `brew install`, then `brew test`. Confirm the expected version using
the installed binary's absolute path from its Homebrew prefix when the tool reports its version. If it does not, check
Homebrew's installed version and compare the installed executable's hash with the binary from the pinned archive. A
successful install verifies the selected archive URL, checksum, extraction, formula install method, and linking; `brew
test` checks behavior after installation. Run these operations without publishing credentials. Existing installations
can make `brew install` skip work; use a fresh environment, or preserve and deliberately account for existing state.

For an upgrade test, install an older release first, replace only the test tap's formula with the newer generated
candidate, then use `brew upgrade` and repeat the version and functional checks. A first-time install of the new release
is not evidence that the upgrade path passed. Keep the production tap separate throughout.

Record the tooling commit, selected release and hashes, generated formula digest, OS/architecture, commands, and
outcomes. If the candidate formula is an uncommitted scratch output, state that explicitly and use its digest to bind
the evidence to its bytes. Do not suggest that the tooling commit alone identifies an uncommitted generated formula.

## Platform coverage

Run native installation checks for each platform you intend to claim as verified. Linux x86-64 success does not prove
Linux ARM64 or either macOS archive works. Downloading and hashing all platform archives is useful integrity coverage,
but is not executable coverage. A local Mac and separate Linux workers are fine; the same explicit config and formula
can be tested on each.

A minimal Ubuntu machine needs Homebrew's documented bootstrap packages (`build-essential`, `procps`, `curl`, `file`,
and `git`) plus working CA certificates. Run Homebrew as an ordinary user at its supported Linux prefix. A prebuilt
image can save bootstrap time; start each acceptance run without the target formula installed. Homebrew publishes
Ubuntu-specific images such as `ghcr.io/homebrew/ubuntu24.04:latest`; resolve and record the image digest, and inspect
its OS and Homebrew version rather than assuming that any image called `latest` is current. Check the worker's actual
architecture with `uname -m` before claiming coverage. Do not assume a sandbox provider offers ARM workers.

Record the Ubuntu/glibc baseline. A successful test on a new distribution does not prove an older supported system can
load the binary. Similarly, an emulated test should be identified as emulated rather than reported as native coverage.

## Activate one tool

After the tooling and candidate have been reviewed, disable that tool's upstream formula-push job and enable its entry
in live pull.toml with the generated formula in a dedicated migration change. Coordinate the two so there is one owner
for the formula. The upstream project may keep using dist for its builds and GitHub releases; only tap publication needs
to change. Do not disable other tools or revoke a shared credential still used by them.

During piecemeal migration, legacy publishers retain repository-wide write access. The owner accepts this transition
state. Once every publisher has migrated, credential revocation and enforcing the human merge gate can be addressed
explicitly. There is no automatic poller or release-selection service in this workflow.

## References

- [Homebrew taps](https://docs.brew.sh/Taps) explains the Git checkout model.
- [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux) documents bootstrap and prefix requirements.
- [Formula cookbook](https://docs.brew.sh/Formula-Cookbook) documents installed-tool test blocks.
- [Homebrew support tiers](https://docs.brew.sh/Support-Tiers) describes current platform requirements.
- [Homebrew's own Linux test workflow](https://github.com/Homebrew/brew/blob/main/.github/workflows/tests.yml)
  identifies the Ubuntu container images used upstream.
- [Immutable GitHub releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
  can prevent asset replacement after publication; recorded hashes still bind this tap's accepted bytes.
