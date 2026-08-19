#!/usr/bin/env bash
# Fetch the external soft cores used by the SoC.

set -euo pipefail

# Clone into third_party regardless of where this script is called from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/third_party"

# clone_core <name> <url> <revision>
# Clone into $CORES_DIR/<name> at the revision recorded in third_party/README.md.
# Existing vendored cores are left untouched.
clone_core() {
    local name="$1" url="$2" revision="$3" dest="$CORES_DIR/$1"
    if [ -d "$dest" ]; then
        echo "Skipping $name (already present at $dest)"
        return
    fi
    echo "Cloning $name into $dest..."
    git clone "$url" "$dest"
    git -C "$dest" checkout --detach "$revision"
}

# fx68k 68000 soft core
clone_core fx68k https://github.com/ijor/fx68k.git 0602ee4

echo "Done."
