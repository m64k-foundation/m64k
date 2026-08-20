#!/usr/bin/env python3
"""Check local documentation links and retired active-tree references."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DOCUMENTS = [REPOSITORY_ROOT / "README.md", *sorted((REPOSITORY_ROOT / "docs" / "m64k").glob("*.md")), REPOSITORY_ROOT / "references" / "manuals" / "README.md"]
LINK_PATTERN = re.compile(r"\[[^]]*]\(([^)]+)\)")
RETIRED_ACTIVE_REFERENCES = (
    "rtl/m68k/",
    "sim/m68k/",
    "third_party/fx68k",
    "make m68k-m00",
    "make linux-m00",
)


def local_link_target(document: Path, raw_target: str) -> Path | None:
    target = raw_target.strip().strip("<>").split("#", 1)[0]
    if not target or "://" in target or target.startswith("mailto:"):
        return None
    return (document.parent / target).resolve()


def main() -> int:
    failures: list[str] = []

    for document in DOCUMENTS:
        text = document.read_text(encoding="utf-8")

        for retired_reference in RETIRED_ACTIVE_REFERENCES:
            if retired_reference in text:
                failures.append(f"{document.relative_to(REPOSITORY_ROOT)}: retired active-tree reference {retired_reference!r}")

        for raw_target in LINK_PATTERN.findall(text):
            target = local_link_target(document, raw_target)
            if target is not None and not target.exists():
                failures.append(
                    f"{document.relative_to(REPOSITORY_ROOT)}: broken local link {raw_target!r} -> {target}"
                )

    if failures:
        for failure in failures:
            print(f"documentation error: {failure}", file=sys.stderr)
        return 1

    print(f"M64K documentation valid: {len(DOCUMENTS)} files, no broken local links or retired active-tree references")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
