#!/usr/bin/env python3
"""Convert a binary image to one byte per line for SystemVerilog readmemh."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    data = args.input.read_bytes()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(f"{byte:02x}\n" for byte in data),
                           encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
