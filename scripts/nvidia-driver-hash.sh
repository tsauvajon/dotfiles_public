#!/usr/bin/env bash
# Print the SRI sha256 of an NVIDIA Linux driver `.run` installer.
#
# Usage:
#   scripts/nvidia-driver-hash.sh <version>
#
# Example:
#   scripts/nvidia-driver-hash.sh 595.71.05
#
# When you bump `version` in `_module.args.nixglNvidia` in
# `home/hosts/linux.nix`, also bump `hash` to whatever this script
# prints. Without a matching hash, nixGL falls
# back to `builtins.fetchurl` and pure evaluation of `thomas-linux`
# breaks (see `home/lib/wrap-with-nixgl.nix`).
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $(basename "$0") <version>" >&2
    echo "example: $(basename "$0") 595.71.05" >&2
    exit 2
fi

version="$1"
url="https://download.nvidia.com/XFree86/Linux-x86_64/${version}/NVIDIA-Linux-x86_64-${version}.run"

echo "Fetching ${url}" >&2

base32_hash="$(nix-prefetch-url --type sha256 "${url}")"
sri_hash="$(nix hash convert --to sri --hash-algo sha256 "${base32_hash}")"

cat <<EOF
version: ${version}
url:     ${url}
sri:     ${sri_hash}

Paste into home/hosts/linux.nix:

  _module.args.nixglNvidia = {
    version = "${version}";
    hash = "${sri_hash}";
  };
EOF
