#!/usr/bin/env python3
"""Mutation tests for the outstanding-uop and completion contract."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from check_uop_completion_contract import UopCompletionContractError, validate_contract  # noqa: E402


CONTRACT_PATH = "docs/m64k/contracts/outstanding-uop-completion-v1.json"
SCHEMA_PATH = "docs/m64k/contracts/outstanding-uop-completion-schema-v1.json"
REQUIRED_PATHS = (
    CONTRACT_PATH,
    SCHEMA_PATH,
    "docs/m64k/contracts/rob-allocation-lifetime-v1.json",
    "isa/native/m64k-native-v1.json",
    "rtl/packages/m64k_arch_types_pkg.sv",
    "rtl/core/execute/common/m64k_execute_backend_pkg.sv",
)


class UopCompletionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository = Path(self.temporary_directory.name)
        for relative_path in REQUIRED_PATHS:
            destination = self.repository / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative_path, destination)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def mutate_contract(self, keys: tuple[str, ...], value: object) -> None:
        path = self.repository / CONTRACT_PATH
        document = json.loads(path.read_text(encoding="utf-8"))
        target = document
        for key in keys[:-1]:
            target = target[key]
        target[keys[-1]] = value
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    def assert_contract_mutation_rejected(self, keys: tuple[str, ...], value: object) -> None:
        self.mutate_contract(keys, value)
        with self.assertRaises(UopCompletionContractError):
            validate_contract(self.repository)

    def assert_rtl_width_mutation_rejected(self, relative_path: str, parameter_name: str, current_width: int, replacement_width: int) -> None:
        path = self.repository / relative_path
        source = path.read_text(encoding="utf-8")
        current_assignment = f"{parameter_name} = {current_width}"
        replacement_assignment = f"{parameter_name} = {replacement_width}"
        self.assertIn(current_assignment, source)
        path.write_text(source.replace(current_assignment, replacement_assignment, 1), encoding="utf-8")
        with self.assertRaises(UopCompletionContractError):
            validate_contract(self.repository)

    def test_current_contract_is_valid(self) -> None:
        validate_contract(self.repository)

    def test_contract_rejects_unknown_field(self) -> None:
        path = self.repository / CONTRACT_PATH
        document = json.loads(path.read_text(encoding="utf-8"))
        document["test_escape"] = True
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        with self.assertRaises(UopCompletionContractError):
            validate_contract(self.repository)

    def test_schema_must_remain_strict(self) -> None:
        path = self.repository / SCHEMA_PATH
        document = json.loads(path.read_text(encoding="utf-8"))
        document["properties"]["completion"]["additionalProperties"] = True
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        with self.assertRaises(UopCompletionContractError):
            validate_contract(self.repository)

    def test_single_thread_projection_cannot_replace_smt_identity(self) -> None:
        self.assert_contract_mutation_rejected(("topology", "hardware_threads_per_core"), 1)

    def test_rob_capacity_cannot_be_reduced(self) -> None:
        self.assert_contract_mutation_rejected(("topology", "rob_entries_per_core"), 128)

    def test_completion_bandwidth_cannot_be_hidden(self) -> None:
        self.assert_contract_mutation_rejected(("topology", "completion_lanes"), 4)

    def test_allocation_sequence_cannot_be_truncated(self) -> None:
        self.assert_contract_mutation_rejected(("identity", "allocation_sequence_bits"), 16)

    def test_rtl_core_identity_width_must_match_exactly(self) -> None:
        self.assert_rtl_width_mutation_rejected("rtl/packages/m64k_arch_types_pkg.sv", "M64K_CORE_ID_WIDTH", 6, 7)

    def test_rtl_hardware_thread_identity_width_must_match_exactly(self) -> None:
        self.assert_rtl_width_mutation_rejected("rtl/packages/m64k_arch_types_pkg.sv", "M64K_HARDWARE_THREAD_ID_WIDTH", 2, 3)

    def test_rtl_rob_index_width_must_match_exactly(self) -> None:
        self.assert_rtl_width_mutation_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "M64K_BACKEND_ROB_INDEX_WIDTH", 8, 9)

    def test_rtl_rob_generation_width_must_match_exactly(self) -> None:
        self.assert_rtl_width_mutation_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "M64K_BACKEND_ROB_GENERATION_WIDTH", 8, 9)

    def test_rtl_allocation_sequence_width_must_match_exactly(self) -> None:
        self.assert_rtl_width_mutation_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH", 64, 63)

    def test_rtl_uop_index_width_must_match_exactly(self) -> None:
        self.assert_rtl_width_mutation_rejected("rtl/core/execute/common/m64k_execute_backend_pkg.sv", "M64K_BACKEND_UOP_INDEX_WIDTH", 4, 5)

    def test_uop_index_is_part_of_membership_identity(self) -> None:
        self.assert_contract_mutation_rejected(
            ("identity", "uop_fields"),
            ["core-id", "hardware-thread-id", "rob-index", "rob-generation", "allocation-sequence"],
        )

    def test_hash_match_cannot_replace_exact_identity(self) -> None:
        self.assert_contract_mutation_rejected(("identity", "equality"), "truncated-hash")

    def test_lifetime_match_is_mandatory(self) -> None:
        self.assert_contract_mutation_rejected(
            ("completion", "acceptance_requires"),
            ["registered-member", "outstanding-not-completed", "unique-completion-lane", "not-released-or-recovered", "exact-terminal-payload"],
        )

    def test_completed_state_cannot_be_omitted(self) -> None:
        self.assert_contract_mutation_rejected(
            ("completion", "acceptance_requires"),
            ["rob-lifetime-match", "registered-member", "unique-completion-lane", "not-released-or-recovered", "exact-terminal-payload"],
        )

    def test_duplicate_completion_cannot_publish_again(self) -> None:
        self.assert_contract_mutation_rejected(("completion", "duplicate_completion"), "accept-with-idempotent-writeback")

    def test_manifest_requires_exact_terminal_payload(self) -> None:
        self.assert_contract_mutation_rejected(("completion", "success_payload"), "accept-any-subset-of-registered-roles")

    def test_duplicate_result_roles_cannot_collapse_into_a_mask(self) -> None:
        self.assert_contract_mutation_rejected(("completion", "result_role_uniqueness"), "duplicate-roles-collapse-into-mask")

    def test_fault_cannot_publish_success_destinations(self) -> None:
        self.assert_contract_mutation_rejected(("completion", "fault_payload"), "typed-fault-with-optional-data-publication")

    def test_unsealed_membership_cannot_look_complete(self) -> None:
        self.assert_contract_mutation_rejected(("membership", "membership_closure"), "implicit-when-current-members-complete")

    def test_tracker_cannot_authorize_retirement(self) -> None:
        self.assert_contract_mutation_rejected(("ownership_separation", "retirement"), "authorize-when-all-uops-complete")

    def test_squash_must_dominate_every_terminal_effect(self) -> None:
        self.assert_contract_mutation_rejected(("squash_and_reset", "release_and_recovery"), "completion-wins")

    def test_payload_arrays_must_not_require_reset(self) -> None:
        self.assert_contract_mutation_rejected(("squash_and_reset", "payload_reset"), "reset-all-payload-storage")


if __name__ == "__main__":
    unittest.main()
