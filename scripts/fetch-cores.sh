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

# OpenCores 16550-compatible UART (freecores GitHub mirror)
clone_core uart16550 https://github.com/freecores/uart16550.git 2b0ad80

# nand2mario's byte-addressable SDRAM controller for the Tang Nano 20k
clone_core sdram-tang-nano-20k https://github.com/nand2mario/sdram-tang-nano-20k.git 918ae41

# OpenCores tiny_spi SPI master
clone_core tiny_spi https://github.com/freecores/tiny_spi.git 562bf1f

echo "Done."
