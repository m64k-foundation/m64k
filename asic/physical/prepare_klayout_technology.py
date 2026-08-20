#!/usr/bin/env python3
"""Create a target-owned Nangate45 KLayout reader configuration.

The pinned FreePDK45 technology declares a 0.0005 um technology DBU but
overrides the LEF/DEF reader to 0.0001 um. OpenDB emits DEF at 0.0005 um, so
the override creates a real coordinate-unit mismatch during stream merge.
This generator validates the pinned input structure, changes only that reader
override, and writes the generated technology file atomically.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import tempfile
import xml.etree.ElementTree as ElementTree


EXPECTED_DATABASE_UNIT = "0.0005"
PINNED_LEFDEF_READER_UNIT = "0.0001"


def prepare_technology(source: Path, destination: Path) -> None:
    tree = ElementTree.parse(source)
    root = tree.getroot()
    technology_database_unit = root.find("dbu")
    lefdef_database_unit = root.find("./reader-options/lefdef/dbu")

    if technology_database_unit is None or technology_database_unit.text != EXPECTED_DATABASE_UNIT:
        raise ValueError("unexpected Nangate45 technology database unit")
    if lefdef_database_unit is None or lefdef_database_unit.text != PINNED_LEFDEF_READER_UNIT:
        raise ValueError("unexpected pinned LEF/DEF reader database unit")

    lefdef_database_unit.text = EXPECTED_DATABASE_UNIT
    destination.parent.mkdir(parents=True, exist_ok=True)

    temporary_file_descriptor, temporary_file_name = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(temporary_file_descriptor, "wb") as temporary_file:
            tree.write(temporary_file, encoding="utf-8", xml_declaration=True)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_file_name, destination)
    except BaseException:
        Path(temporary_file_name).unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()

    prepare_technology(arguments.source, arguments.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
