#!/usr/bin/env bash
# Run only in a disposable Linux Homebrew container. The mounted inputs are
# generated formulas from one reviewed tooling revision; no host tap is mounted.
set -u
set -o pipefail

# Arguments: inputs directory holding new/treeward.rb and old/treeward.rb, then
# the versions those two formulas are expected to install. Versions are
# explicit rather than parsed from the formulas so a wrong input fails loudly
# instead of being verified against itself.
test "$#" -eq 3 || exit 2
acceptance_inputs=$1
new_version=$2
old_version=$3
formula=local/pull-check/treeward
tap_dir="$(brew --repository)/Library/Taps/local/homebrew-pull-check" || exit 1
mkdir -p "$tap_dir/Formula" || exit 1
git -C "$tap_dir" init --quiet || exit 1

# Homebrew's receipt identifies the selected release. Comparing executable bytes
# closes the gap left by treeward releases that do not implement --version.
verify_installed() {
  local expected_version=$1 installed_prefix resolved_prefix cache_path installed_hash archive_hash
  installed_prefix=$(brew --prefix "$formula") || return 1
  resolved_prefix=$(readlink -f "$installed_prefix") || return 1
  test "${resolved_prefix##*/}" = "$expected_version" || return 1
  brew list --versions "$formula" || return 1
  cache_path=$(brew --cache "$formula") || return 1
  installed_hash=$(sha256sum "$installed_prefix/bin/treeward") || return 1
  archive_hash=$(tar -xOJf "$cache_path" treeward-x86_64-unknown-linux-gnu/treeward | sha256sum) || return 1
  test "${installed_hash%% *}" = "${archive_hash%% *}" || return 1
  printf 'Verified installed executable SHA-256: %s\n' "${installed_hash%% *}"
  # The upgrade baseline may be a formula the upstream publisher pushed, which
  # has no test block; `brew test` errors on such a formula rather than
  # passing vacuously, so skip it there and say so instead of failing the trial.
  if grep -q '^  test do$' "$tap_dir/Formula/treeward.rb"; then
    brew test "$formula" || return 1
  else
    printf 'Formula defines no test block; skipping brew test for %s\n' "$expected_version"
  fi
}

uname -m || exit 1
cat /etc/os-release || exit 1
getconf GNU_LIBC_VERSION || exit 1
brew --version || exit 1

cp "$acceptance_inputs/new/treeward.rb" "$tap_dir/Formula/treeward.rb" || exit 1
brew install "$formula" || exit 1
verify_installed "$new_version" || exit 1
brew uninstall "$formula" || exit 1

cp "$acceptance_inputs/old/treeward.rb" "$tap_dir/Formula/treeward.rb" || exit 1
brew install "$formula" || exit 1
verify_installed "$old_version" || exit 1
cp "$acceptance_inputs/new/treeward.rb" "$tap_dir/Formula/treeward.rb" || exit 1
brew upgrade "$formula" || exit 1
verify_installed "$new_version" || exit 1
printf 'PASS: fresh install, functional tests, and upgrade on native Linux x86-64\n'
