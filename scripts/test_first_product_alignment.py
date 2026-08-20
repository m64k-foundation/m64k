#!/usr/bin/env python3
"""Mutation tests for first-product interface-alignment checks."""

from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from check_first_product_alignment import AlignmentError, validate_alignment  # noqa: E402


REQUIRED_PATHS = (
    "isa/native/m64k-native-v1.json",
    "rtl/packages/m64k_arch_types_pkg.sv",
    "rtl/core/execute/common/m64k_execute_backend_pkg.sv",
    "rtl/interfaces/retirement/m64k_precise_retirement_if.sv",
)


class FirstProductAlignmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository = Path(self.temporary_directory.name)
        for relative_path in REQUIRED_PATHS:
            destination = self.repository / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative_path, destination)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def replace(self, relative_path: str, old: str, new: str) -> None:
        path = self.repository / relative_path
        source = path.read_text(encoding="utf-8")
        self.assertIn(old, source)
        path.write_text(source.replace(old, new, 1), encoding="utf-8")

    def assert_rejected(self, relative_path: str, old: str, new: str) -> None:
        self.replace(relative_path, old, new)
        with self.assertRaises(AlignmentError):
            validate_alignment(self.repository)

    def test_current_interfaces_represent_target(self) -> None:
        validate_alignment(self.repository)

    def test_32_bit_datapath_is_rejected(self) -> None:
        self.assert_rejected("rtl/packages/m64k_arch_types_pkg.sv", "M64K_NATIVE_XLEN = 64", "M64K_NATIVE_XLEN = 32")

    def test_undersized_rob_identity_is_rejected(self) -> None:
        self.assert_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "M64K_BACKEND_ROB_INDEX_WIDTH = 8", "M64K_BACKEND_ROB_INDEX_WIDTH = 7")

    def test_core_identity_width_drift_is_rejected(self) -> None:
        self.assert_rejected("rtl/packages/m64k_arch_types_pkg.sv", "M64K_CORE_ID_WIDTH = 6", "M64K_CORE_ID_WIDTH = 7")

    def test_thread_identity_width_drift_is_rejected(self) -> None:
        self.assert_rejected("rtl/packages/m64k_arch_types_pkg.sv", "M64K_HARDWARE_THREAD_ID_WIDTH = 2", "M64K_HARDWARE_THREAD_ID_WIDTH = 3")

    def test_rob_generation_width_drift_is_rejected(self) -> None:
        self.assert_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "M64K_BACKEND_ROB_GENERATION_WIDTH = 8", "M64K_BACKEND_ROB_GENERATION_WIDTH = 9")

    def test_uop_identity_width_drift_is_rejected(self) -> None:
        self.assert_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "M64K_BACKEND_UOP_INDEX_WIDTH = 4", "M64K_BACKEND_UOP_INDEX_WIDTH = 5")

    def test_missing_allocation_lifetime_identity_is_rejected(self) -> None:
        self.assert_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "allocation_sequence;", "retired_sequence;")

    def test_short_allocation_sequence_is_rejected(self) -> None:
        self.assert_rejected(
            "rtl/core/execute/common/m64k_execute_backend_pkg.sv",
            "M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH = 64",
            "M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH = 16",
        )

    def test_two_lane_retirement_default_is_rejected(self) -> None:
        self.assert_rejected("rtl/interfaces/retirement/m64k_precise_retirement_if.sv", "RETIRE_LANES = 4", "RETIRE_LANES = 2")

    def test_fixed_vector_geometry_in_base_contract_is_rejected(self) -> None:
        path = self.repository / "rtl/packages/m64k_arch_types_pkg.sv"
        source = path.read_text(encoding="utf-8")
        path.write_text(source.replace("package m64k_arch_types_pkg;", "package m64k_arch_types_pkg;\n    localparam int unsigned VLEN = 256;", 1), encoding="utf-8")
        with self.assertRaises(AlignmentError):
            validate_alignment(self.repository)


if __name__ == "__main__":
    unittest.main()
