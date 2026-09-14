#!/usr/bin/env bash
# Prove that a candidate formula installs, upgrades from its predecessor, and
# yields the release the pull configuration records, using an isolated local
# tap on this machine.
#
# usage: formula-upgrade-test.sh TOOL NEW_FORMULA NEW_CONFIG [OLD_FORMULA OLD_VERSION]
#
# NEW_CONFIG is the pull.toml that accompanies NEW_FORMULA. The candidate's
# expected version and expected archive SHA-256 for this host come from there,
# not from the formula, so a formula whose url, sha256, or version line points
# at a different release than the configuration records fails instead of
# verifying itself against its own declarations.
#
# With five arguments the script performs a fresh install of NEW_FORMULA, then
# installs OLD_FORMULA and upgrades to NEW_FORMULA, verifying after each step.
# With three it performs only the fresh install; use that for a tool whose
# formula has no predecessor. The baseline is the starting state rather than
# the thing under test, so its version is supplied by the caller and it is
# only checked against its own archive.
#
# Run only where the tool is not already installed and nothing else depends
# on the Homebrew prefix: a CI runner or a disposable container. The script
# executes the candidate formula's Ruby and the installed binary, so run it
# without publishing credentials. The tap it creates is local-only; no remote
# can update it underneath the test. Needs only bash, git, awk, tar with xz
# support, and sha256sum or shasum, all present on GitHub runners and in
# Homebrew's Linux container image.
set -u
set -o pipefail

case "$#" in
  3 | 5) ;;
  *)
    echo "usage: $0 TOOL NEW_FORMULA NEW_CONFIG [OLD_FORMULA OLD_VERSION]" >&2
    exit 2
    ;;
esac
tool=$1
new_formula=$2
new_config=$3
old_formula=${4-}
old_version=${5-}

formula="local/pull-check/$tool"
tap_dir="$(brew --repository)/Library/Taps/local/homebrew-pull-check" || exit 1

# Portable helpers: macOS ships shasum rather than sha256sum, and the archive
# member to compare against is named by the Rust target triple of this host.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | cut -d' ' -f1
  else
    shasum -a 256 "$@" | cut -d' ' -f1
  fi
}

target_triple() {
  local arch os
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    arm64 | aarch64) arch=aarch64 ;;
    *) return 1 ;;
  esac
  case "$(uname -s)" in
    Darwin) os=apple-darwin ;;
    Linux) os=unknown-linux-gnu ;;
    *) return 1 ;;
  esac
  printf '%s-%s\n' "$arch" "$os"
}

# Prints `version=` (the tag without its v prefix) and `sha256=` (this host's
# archive hash) from the pull configuration. This is not a TOML parser: it
# relies on the fixed shape the updater generates and SPEC.md defines, with
# one `[tools.NAME]` table holding `tag` and one `[tools.NAME.sha256]` table
# holding a key per target. That keeps the script runnable in Homebrew's
# Linux container image, which ships no python3, at the cost of not
# accepting hand-written TOML in other layouts.
read_config() {
  awk -v tool="$tool" -v triple="$1" '
    /^\[/ { section = $0 }
    section == "[tools." tool "]" && $1 == "tag" && $2 == "=" {
      value = $3
      gsub(/"/, "", value)
      sub(/^v/, "", value)
      print "version=" value
    }
    section == "[tools." tool ".sha256]" && $1 == triple && $2 == "=" {
      value = $3
      gsub(/"/, "", value)
      print "sha256=" value
    }
  ' "$new_config"
}

# Homebrew's keg name identifies the installed version. Comparing executable
# bytes with the checksum-verified cached archive closes the gap left by tools
# that do not report their version, and comparing that archive with the
# recorded hash ties the installation to the release the configuration
# accepted. The archive layout `TOOL-TRIPLE/TOOL` is the shared contract in
# SPEC.md that every pull-managed tool publishes; a tool with a different
# layout needs its own case here rather than a weakened check.
#
# $1 expected version; $2 expected archive SHA-256, or empty to check the
# archive only against the formula's own declaration; $3 `require-test` or
# `allow-missing-test`. A formula the upstream publisher pushed may define no
# test block, and `brew test` errors on such a formula rather than passing
# vacuously; that is tolerated for the baseline only. Every formula this
# repository generates must have a test, so the candidate is never exempt.
verify_installed() {
  local expected_version=$1 expected_archive_sha256=$2 test_policy=$3
  local triple installed_prefix resolved_prefix keg cache_path installed_hash archive_hash cached_archive_hash
  triple=$(target_triple) || return 1
  installed_prefix=$(brew --prefix "$formula") || return 1
  resolved_prefix=$(cd "$installed_prefix" && pwd -P) || return 1
  # A formula `revision` appends `_N` to the keg name without changing the
  # upstream version it packages.
  keg=${resolved_prefix##*/}
  case "$keg" in
    "$expected_version" | "$expected_version"_[0-9]*) ;;
    *)
      echo "expected version $expected_version, installed keg is $keg" >&2
      return 1
      ;;
  esac
  brew list --versions "$formula" || return 1
  cache_path=$(brew --cache "$formula") || return 1
  if test -n "$expected_archive_sha256"; then
    cached_archive_hash=$(sha256_of "$cache_path") || return 1
    test "$cached_archive_hash" = "$expected_archive_sha256" || {
      echo "cached archive $cached_archive_hash is not the recorded $triple archive $expected_archive_sha256" >&2
      return 1
    }
    printf 'Cached archive matches recorded SHA-256 for %s\n' "$triple"
  fi
  installed_hash=$(sha256_of "$installed_prefix/bin/$tool") || return 1
  archive_hash=$(tar -xOJf "$cache_path" "$tool-$triple/$tool" | sha256_of) || return 1
  test "$installed_hash" = "$archive_hash" || {
    echo "installed executable $installed_hash does not match archive member $archive_hash" >&2
    return 1
  }
  printf 'Verified installed executable SHA-256: %s\n' "$installed_hash"
  if grep -q '^  test do$' "$tap_dir/Formula/$tool.rb"; then
    brew test "$formula" || return 1
  elif test "$test_policy" = allow-missing-test; then
    printf 'Baseline formula defines no test block; skipping brew test for %s\n' "$expected_version"
  else
    echo "candidate formula defines no test block" >&2
    return 1
  fi
}

# Refuse to run on top of state that could mask a failure: an existing test
# tap or an installed copy of the tool from any other source.
test ! -e "$tap_dir" || {
  echo "refusing to reuse existing $tap_dir" >&2
  exit 1
}
if brew list --versions "$tool" >/dev/null 2>&1; then
  echo "$tool is already installed; use a fresh environment" >&2
  exit 1
fi

triple=$(target_triple) || exit 1
new_version=
new_archive_sha256=
while IFS= read -r line; do
  case "$line" in
    version=*) new_version=${line#version=} ;;
    sha256=*) new_archive_sha256=${line#sha256=} ;;
  esac
done < <(read_config "$triple")
if test -z "$new_version" || test -z "$new_archive_sha256"; then
  echo "could not read tag and $triple sha256 for $tool from $new_config" >&2
  exit 1
fi

uname -m || exit 1
uname -s || exit 1
if test -r /etc/os-release; then
  cat /etc/os-release || exit 1
  getconf GNU_LIBC_VERSION || exit 1
else
  sw_vers || exit 1
fi
brew --version || exit 1

mkdir -p "$tap_dir/Formula" || exit 1
git -C "$tap_dir" init --quiet || exit 1

cp "$new_formula" "$tap_dir/Formula/$tool.rb" || exit 1
brew install "$formula" || exit 1
verify_installed "$new_version" "$new_archive_sha256" require-test || exit 1

if test -z "$old_formula"; then
  printf 'PASS: fresh install of %s %s and functional test on %s (no upgrade baseline supplied)\n' \
    "$tool" "$new_version" "$triple"
  exit 0
fi

# `brew upgrade` is a no-op when the baseline already declares the candidate's
# version, so a same-version formula change cannot exercise the upgrade path.
# Say so rather than report an upgrade that never happened.
if test "$old_version" = "$new_version"; then
  printf 'PASS: fresh install of %s %s and functional test on %s (baseline declares the same version; upgrade path not exercised)\n' \
    "$tool" "$new_version" "$triple"
  exit 0
fi

brew uninstall "$formula" || exit 1
cp "$old_formula" "$tap_dir/Formula/$tool.rb" || exit 1
brew install "$formula" || exit 1
verify_installed "$old_version" "" allow-missing-test || exit 1
cp "$new_formula" "$tap_dir/Formula/$tool.rb" || exit 1
brew upgrade "$formula" || exit 1
verify_installed "$new_version" "$new_archive_sha256" require-test || exit 1
printf 'PASS: fresh install, functional test, and upgrade of %s from %s to %s on %s\n' \
  "$tool" "$old_version" "$new_version" "$triple"
