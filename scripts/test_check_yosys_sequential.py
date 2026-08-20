from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from scripts.check_yosys_sequential import count_sequential_cells


class YosysSequentialStateTests(unittest.TestCase):
    def write_stat(self, directory: str, cells: dict[str, int]) -> Path:
        path = Path(directory) / "stat.json"
        path.write_text(json.dumps({"modules": {"\\dut": {"num_cells_by_type": cells}}}), encoding="utf-8")
        return path

    def test_counts_dff_families_and_excludes_combinational_cells(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            stat = self.write_stat(directory, {"$_DFF_P_": 3, "$_SDFFE_PP0P_": 462, "$_AND_": 1000})
            self.assertEqual(count_sequential_cells(stat, "dut"), 465)

    def test_rejects_missing_top(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            stat = self.write_stat(directory, {"$_DFF_P_": 1})
            with self.assertRaisesRegex(ValueError, "no top module"):
                count_sequential_cells(stat, "missing")

    def test_rejects_invalid_cell_count(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            stat = self.write_stat(directory, {"$_DFF_P_": -1})
            with self.assertRaisesRegex(ValueError, "invalid cell-type count"):
                count_sequential_cells(stat, "dut")


if __name__ == "__main__":
    unittest.main()
