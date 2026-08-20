#!/usr/bin/env python3
"""Fail unless a synthesized Yosys module retains the expected sequential state."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


SEQUENTIAL_CELL_PATTERN = re.compile(r"^\$_[A-Z]*DFF")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("stat", type=Path)
    parser.add_argument("--top", required=True)
    parser.add_argument("--minimum-cells", required=True, type=int)
    return parser.parse_args()


def count_sequential_cells(stat_path: Path, top: str) -> int:
    document = json.loads(stat_path.read_text(encoding="utf-8"))
    modules = document.get("modules")
    if not isinstance(modules, dict):
        raise ValueError("Yosys stat JSON has no modules object")

    module = modules.get(f"\\{top}")
    if not isinstance(module, dict):
        raise ValueError(f"Yosys stat JSON has no top module named {top}")

    cells_by_type = module.get("num_cells_by_type")
    if not isinstance(cells_by_type, dict):
        raise ValueError(f"Yosys stat JSON has no cell-type counts for {top}")

    sequential_cells = 0
    for cell_type, count in cells_by_type.items():
        if not isinstance(cell_type, str) or not isinstance(count, int) or count < 0:
            raise ValueError("Yosys stat JSON contains an invalid cell-type count")
        if SEQUENTIAL_CELL_PATTERN.match(cell_type):
            sequential_cells += count

    return sequential_cells


def main() -> int:
    arguments = parse_arguments()
    if arguments.minimum_cells <= 0:
        raise SystemExit("--minimum-cells must be positive")

    try:
        sequential_cells = count_sequential_cells(arguments.stat, arguments.top)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"sequential-state check failed: {error}") from error

    if sequential_cells < arguments.minimum_cells:
        raise SystemExit(
            f"sequential-state check failed: {arguments.top} contains {sequential_cells} sequential cells; expected at least {arguments.minimum_cells}"
        )

    print(f"PASS: {arguments.top} retains {sequential_cells} synthesized sequential cells")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
