#!/usr/bin/env bash
# Build the hyprbaric AppMenu companion plugin against the host Hyprland SDK
# and install only the compiled .so to /etc/hyprbaric as root. Never loads it.
#
# usage: build-hyprbaric-appmenu.sh <source-dir>
#   <source-dir> must contain CMakeLists.txt, src/main.cpp, and protocols/.
set -euo pipefail

usage() {
    printf 'usage: %s <source-dir>\n' "${0##*/}" >&2
    printf '\n' >&2
    printf 'Builds the Hyprbaric AppMenu Hyprland plugin from <source-dir> with\n' >&2
    printf 'host tools (/usr/bin/{cc,c++,make,pkg-config,wayland-scanner} and cmake\n' >&2
    printf 'from PATH) in a user-owned temp directory, then installs the single\n' >&2
    printf 'compiled hyprbaric-appmenu.so to /etc/hyprbaric/ via sudo.\n' >&2
    printf '\n' >&2
    printf 'The plugin is never loaded; hyprctl is untouched.\n' >&2
}

die() {
    printf 'build-hyprbaric-appmenu: %s\n' "$1" >&2
    exit 1
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [ "$#" -ne 1 ]; then
    usage
    exit 64
fi

source_dir=$1
if [ ! -d "$source_dir" ]; then
    die "source directory does not exist: $source_dir"
fi

for entry in CMakeLists.txt src/main.cpp protocols; do
    if [ ! -e "$source_dir/$entry" ]; then
        die "missing required entry in $source_dir: $entry"
    fi
done

for tool in cmake /usr/bin/cc /usr/bin/c++ /usr/bin/make /usr/bin/pkg-config /usr/bin/wayland-scanner sudo; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        die "required tool not found on PATH or at host path: $tool"
    fi
done

if ! /usr/bin/pkg-config --exists hyprland; then
    die "host Hyprland SDK not found: /usr/bin/pkg-config cannot resolve the hyprland module (install hyprland headers/pkg-config file)"
fi

build_root=$(mktemp -d "${XDG_CACHE_HOME:-${TMPDIR:-/tmp}}/hyprbaric-appmenu-build.XXXXXX")
trap 'rm -rf "$build_root"' EXIT

printf '==> Configuring hyprbaric-appmenu from %s\n' "$source_dir"
cmake -S "$source_dir" -B "$build_root/build" \
    -DHYPRBARIC_APPMENU_BUILD_PROBES=OFF \
    -DCMAKE_C_COMPILER=/usr/bin/cc \
    -DCMAKE_CXX_COMPILER=/usr/bin/c++ \
    -DCMAKE_MAKE_PROGRAM=/usr/bin/make \
    -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkg-config \
    -DWAYLAND_SCANNER=/usr/bin/wayland-scanner

printf '==> Building hyprbaric-appmenu\n'
cmake --build "$build_root/build" --parallel 2

artifact="$build_root/build/hyprbaric-appmenu.so"
if [ ! -f "$artifact" ]; then
    die "build did not produce hyprbaric-appmenu.so in $build_root/build"
fi

printf '==> Installing %s to /etc/hyprbaric/hyprbaric-appmenu.so\n' "$artifact"
sudo install -d -m 0755 /etc/hyprbaric
stage=""
stage=$(mktemp /etc/hyprbaric/.hyprbaric-appmenu.so.XXXXXX)
trap 'rm -rf "$build_root"; [ -z "$stage" ] || sudo rm -f "$stage"' EXIT
sudo install -m 0644 "$artifact" "$stage"
sudo mv "$stage" /etc/hyprbaric/hyprbaric-appmenu.so
stage=""

printf '==> Installed /etc/hyprbaric/hyprbaric-appmenu.so (not loaded; restart or reload hyprbaric to use it)\n'
