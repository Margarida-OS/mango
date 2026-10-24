#!/usr/bin/env bash
# Writes a debian/changelog from the git history of the current checkout.
# debian/changelog is generated, not tracked, so every build names the commit it
# was built from. Without arguments it writes packaging/debian/changelog; the
# build script passes the staged copy instead.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
cd "$repo"

version=$(git describe --tags --abbrev=0 | sed 's/^v//')
commit=$(git rev-parse --short HEAD)
date=$(date -R)
changes=("Snapshot of ${version} plus the Margarida-OS patches (tree ${commit}).")

if ! git diff --quiet -- packaging; then
  changes+=("Includes uncommitted changes under packaging/.")
fi

target=${1:-$repo/packaging/debian/changelog}
{
  printf 'modular-mango (%s) unstable; urgency=medium\n\n' "$version"
  for change in "${changes[@]}"; do
    printf '  * %s\n' "$change"
  done
  printf '\n -- Denys Madureira <denys@margarida-os.dev>  %s\n' "$date"
} > "$target"

printf 'generated packaging/debian/changelog for %s (tree %s)\n' "$version" "$commit"