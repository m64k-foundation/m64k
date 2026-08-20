#!/usr/bin/env python3
"""Unit tests for target-owned KLayout DBU preparation."""

from __future__ import annotations

from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree

from asic.physical.prepare_klayout_technology import prepare_technology


VALID_TEMPLATE = """<?xml version="1.0"?>
<technology>
  <dbu>0.0005</dbu>
  <reader-options><lefdef><dbu>0.0001</dbu></lefdef></reader-options>
</technology>
"""


class PrepareKlayoutTechnologyTest(unittest.TestCase):
    def test_changes_only_reader_database_unit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "source.lyt"
            destination = root / "destination.lyt"
            source.write_text(VALID_TEMPLATE, encoding="utf-8")

            prepare_technology(source, destination)

            generated_root = ElementTree.parse(destination).getroot()
            self.assertEqual(generated_root.findtext("dbu"), "0.0005")
            self.assertEqual(generated_root.findtext("./reader-options/lefdef/dbu"), "0.0005")

    def test_rejects_unexpected_pinned_template(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "source.lyt"
            destination = root / "destination.lyt"
            source.write_text(VALID_TEMPLATE.replace("0.0001", "0.0002"), encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "unexpected pinned LEF/DEF reader database unit"):
                prepare_technology(source, destination)

            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
