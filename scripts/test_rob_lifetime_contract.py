#!/usr/bin/env python3
"""Mutation tests for the ROB allocation-lifetime implementation contract."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from check_rob_lifetime_contract import LifetimeContractError, validate_contract  # noqa: E402


REQUIRED_PATHS = (
    "docs/m64k/contracts/rob-allocation-lifetime-v1.json",
    "docs/m64k/contracts/rob-allocation-lifetime-schema-v1.json",
    "isa/native/m64k-native-v1.json",
)


class RobLifetimeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository = Path(self.temporary_directory.name)
        for relative_path in REQUIRED_PATHS:
            destination = self.repository / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative_path, destination)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def mutate(self, keys: tuple[str, ...], value: object) -> None:
        path = self.repository / REQUIRED_PATHS[0]
        document = json.loads(path.read_text(encoding="utf-8"))
        target = document
        for key in keys[:-1]:
            target = target[key]
        target[keys[-1]] = value
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    def assert_mutation_rejected(self, keys: tuple[str, ...], value: object) -> None:
        self.mutate(keys, value)
        with self.assertRaises(LifetimeContractError):
            validate_contract(self.repository)

    def test_current_contract_is_valid(self) -> None:
        validate_contract(self.repository)

    def test_128_entries_cannot_claim_rob_192(self) -> None:
        self.assert_mutation_rejected(("topology", "entries"), 128)

    def test_single_thread_table_is_rejected(self) -> None:
        self.assert_mutation_rejected(("topology", "hardware_threads"), 1)

    def test_four_validation_lanes_are_rejected(self) -> None:
        self.assert_mutation_rejected(("topology", "validation_lanes"), 4)

    def test_partial_recovery_mask_is_rejected(self) -> None:
        self.assert_mutation_rejected(("topology", "recovery_mask_bits"), 4)

    def test_short_allocation_sequence_is_rejected(self) -> None:
        self.assert_mutation_rejected(("identity", "allocation_sequence_bits"), 16)

    def test_wider_uncontracted_allocation_sequence_is_rejected(self) -> None:
        self.assert_mutation_rejected(("identity", "allocation_sequence_bits"), 65)

    def test_unknown_contract_field_is_rejected(self) -> None:
        path = self.repository / REQUIRED_PATHS[0]
        document = json.loads(path.read_text(encoding="utf-8"))
        document["test_escape"] = True
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        with self.assertRaises(LifetimeContractError):
            validate_contract(self.repository)

    def test_missing_thread_identity_is_rejected(self) -> None:
        self.assert_mutation_rejected(("identity", "stored_fields"), ["rob-generation", "allocation-sequence"])

    def test_unchecked_rollover_is_rejected(self) -> None:
        self.assert_mutation_rejected(("identity", "rollover"), "natural-modulo-wrap")

    def test_release_must_suppress_same_cycle_match(self) -> None:
        self.assert_mutation_rejected(("cycle_semantics", "release_suppresses_match"), False)

    def test_recovery_must_dominate_allocation(self) -> None:
        self.assert_mutation_rejected(("cycle_semantics", "recovery_dominance"), "allocation-wins")

    def test_duplicate_completion_is_not_claimed_by_this_primitive(self) -> None:
        path = self.repository / REQUIRED_PATHS[0]
        document = json.loads(path.read_text(encoding="utf-8"))
        document["non_claims"].remove("duplicate-completion-detection")
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        with self.assertRaises(LifetimeContractError):
            validate_contract(self.repository)


if __name__ == "__main__":
    unittest.main()
