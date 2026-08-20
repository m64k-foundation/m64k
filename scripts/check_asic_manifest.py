#!/usr/bin/env python3
"""Validate a first-party ASIC source manifest and print its source paths."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ALLOWED_PREFIX = "rtl/"
PORTABLE_SOURCE = re.compile(r"^rtl/[A-Za-z0-9_.\-/]+\.(?:sv|v)$")


class ManifestValidationError(ValueError):
    """Report every structural error in one source manifest."""

    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors))
        self.errors = tuple(errors)


def validated_source_names(manifest: Path) -> list[str]:
    """Return canonical first-party source names or raise a closed validation error."""

    lines = manifest.resolve().read_text(encoding="utf-8").splitlines()
    sources: list[str] = []
    resolved_sources: set[Path] = set()
    errors: list[str] = []

    for line_number, raw_line in enumerate(lines, start=1):
        source = raw_line.strip()
        if not source or source.startswith("#"):
            continue
        if not PORTABLE_SOURCE.fullmatch(source):
            errors.append(f"line {line_number}: source must use a portable rtl/*.sv or rtl/*.v path: {source}")
            continue
        if source.startswith("/") or ".." in Path(source).parts:
            errors.append(f"line {line_number}: source must be repository-relative: {source}")
            continue
        if not source.startswith(ALLOWED_PREFIX):
            errors.append(f"line {line_number}: production RTL must reside below {ALLOWED_PREFIX}: {source}")
            continue

        source_path = REPOSITORY_ROOT / source
        try:
            resolved_source = source_path.resolve(strict=True)
            resolved_source.relative_to(REPOSITORY_ROOT.resolve())
        except (OSError, ValueError):
            errors.append(f"line {line_number}: source resolves outside the repository or does not exist: {source}")
            continue
        if not resolved_source.is_file():
            errors.append(f"line {line_number}: source does not exist: {source}")
        elif source in sources or resolved_source in resolved_sources:
            errors.append(f"line {line_number}: duplicate source: {source}")
        else:
            sources.append(source)
            resolved_sources.add(resolved_source)

    if not sources:
        errors.append("manifest contains no production RTL")
    if errors:
        raise ManifestValidationError(errors)

    return sources


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--print-sources", action="store_true")
    arguments = parser.parse_args()

    try:
        sources = validated_source_names(arguments.manifest)
    except OSError as error:
        print(f"ASIC manifest error: {error}", file=sys.stderr)
        return 2
    except ManifestValidationError as validation_error:
        for error in validation_error.errors:
            print(f"ASIC manifest error: {error}", file=sys.stderr)
        return 1

    if arguments.print_sources:
        print(" ".join(sources))
    else:
        print(f"ASIC manifest: {len(sources)} first-party RTL sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
