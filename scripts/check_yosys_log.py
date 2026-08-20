#!/usr/bin/env python3
"""Fail a first-party Yosys gate when its log contains a warning."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


WARNING = re.compile(r"(?:^|\s)Warning:", re.IGNORECASE)
ABC_COMBINATIONAL_WARNING = 'ABC: Warning: The network is combinational (run "fraig" or "fraig_sweep").'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--allow-one-abc-combinational", action="store_true")
    arguments = parser.parse_args()

    try:
        warnings = [
            line
            for line in arguments.log.read_text(encoding="utf-8", errors="replace").splitlines()
            if WARNING.search(line)
        ]
    except OSError as error:
        print(f"Yosys log error: {error}", file=sys.stderr)
        return 2

    allowed_count = 0
    if arguments.allow_one_abc_combinational:
        unexpected = []
        for warning in warnings:
            if warning.strip() == ABC_COMBINATIONAL_WARNING:
                allowed_count += 1
            else:
                unexpected.append(warning)
        warnings = unexpected
        if allowed_count != 1:
            print(f"Yosys warning gate expected exactly one classified ABC diagnostic, found {allowed_count}", file=sys.stderr)
            return 1

    if warnings:
        print(f"Yosys warning gate failed with {len(warnings)} diagnostic(s):", file=sys.stderr)
        for warning in warnings:
            print(warning, file=sys.stderr)
        return 1

    print("PASS: Yosys emitted no unclassified warnings")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
