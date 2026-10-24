#!/usr/bin/env bash
# Builds modular-mango_<version>_amd64.deb inside a Debian unstable container.
#
# The tree is assembled from git and the packaging directory, so the container
# never sees the checkout: it builds what is committed plus what lives in
# packaging/debian. The staged source is mounted at /src and dpkg-buildpackage
# writes the debs next to it, in the same temporary directory. Nothing under the
# checkout is modified, so no file ends up owned by root.
set -euo pipefail

image=${IMAGE:-docker.io/library/debian:sid}
packaging_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(git -C "$packaging_dir" rev-parse --show-toplevel)
out="${OUT_DIR:-$repo/dist}"

if [[ -n $(git -C "$repo" status --porcelain --untracked-files=no) ]]; then
  printf 'error: tracked files have uncommitted changes, commit or stash first\n' >&2
  exit 1
fi

work=$(mktemp -d -t modular-mango-deb.XXXXXX)
stage="$work/src"
container="modular-mango-deb-$$"
# The build runs as root and only writes to this volume, never to $work.
output_volume="modular-mango-deb-output-$$"

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  # dpkg-buildpackage leaves root-owned artefacts in the source tree, and the
  # build script cannot remove them from the host.
  docker run --rm -v "$work:/work" "$image" rm -rf /work/src/debian >/dev/null 2>&1 || true
  docker volume rm -f "$output_volume" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$stage/debian" "$out"
git -C "$repo" archive HEAD | tar -x -C "$stage"
cp -a "$packaging_dir"/. "$stage/debian/"
bash "$packaging_dir/generate-changelog.sh" "$stage/debian/changelog"

docker run --name "$container" \
  -v "$stage:/src" \
  -v "$output_volume:/out" \
  -w /src \
  "$image" bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    sed -i -E "s/^Components: .*/Components: main/" /etc/apt/sources.list.d/debian.sources
    echo "deb-src http://deb.debian.org/debian sid main" >> /etc/apt/sources.list.d/debian.sources
    apt-get update
    apt-get install -y --no-install-recommends \
      build-essential dpkg-dev debhelper devscripts fakeroot ninja-build meson pkgconf
    apt-get build-dep -y .
    dpkg-buildpackage -us -uc -b -d
    install -m644 -o "$1" -g "$2" /src/../modular-mango_*_*.deb /out/
  ' _ "$(id -u)" "$(id -g)"

# Pull the debs out of the volume instead of copying from the host, which would
# duplicate the base filesystem into the output directory.
docker cp "$container:/out/." "$out/"
ls -l "$out"/modular-mango_*.deb