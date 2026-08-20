#!/usr/bin/env python3
"""Positive, contradiction, and release-gate tests for M64K-v1 contracts."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

from check_m64k_native_contracts import ContractError, load_object, validate_contract, validate_cut_line_inventory, validate_instruction_semantic_contract, validate_registry, validate_semantic_baseline, validate_source_manifest  # noqa: E402


ROOT = SCRIPT_DIRECTORY.parent
REGISTRY = ROOT / "isa/native/registry.json"
CONTRACT = ROOT / "isa/native/m64k-native-v1.json"
CUT_LINE = ROOT / "isa/native/mc68060-semantic-cut-line.json"
MANUAL_MANIFEST = ROOT / "references/manuals/manifest.json"


class NativeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = load_object(CONTRACT)

    def assert_invalid(self, mutation) -> None:
        candidate = copy.deepcopy(self.contract)
        mutation(candidate)
        with self.assertRaises(ContractError):
            validate_contract(candidate, "M64K-v1")

    def assert_cut_line_invalid(self, mutation) -> None:
        candidate = load_object(CUT_LINE)
        mutation(candidate)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mc68060-semantic-cut-line.json"
            path.write_text(json.dumps(candidate), encoding="utf-8")
            with self.assertRaises(ContractError):
                validate_cut_line_inventory(path, MANUAL_MANIFEST)

    def assert_semantic_invalid(self, reference_index, mutation, schema_mutation=None) -> None:
        reference = self.contract["semantic_contracts"][reference_index]
        semantics_path = ROOT / "isa/native" / reference["path"]
        candidate = load_object(semantics_path)
        mutation(candidate)
        schema_path = ROOT / "isa/native" / reference["validation_schema"]
        if schema_mutation is None:
            with self.assertRaises(ContractError):
                validate_instruction_semantic_contract(
                    candidate,
                    reference,
                    semantics_path,
                    schema_path,
                    MANUAL_MANIFEST,
                    reference["contract_id"],
                )
            return

        schema = load_object(schema_path)
        schema_mutation(schema)
        with tempfile.TemporaryDirectory() as directory:
            mutated_schema_path = Path(directory) / schema_path.name
            mutated_schema_path.write_text(json.dumps(schema), encoding="utf-8")
            with self.assertRaises(ContractError):
                validate_instruction_semantic_contract(
                    candidate,
                    reference,
                    semantics_path,
                    mutated_schema_path,
                    MANUAL_MANIFEST,
                    reference["contract_id"],
                )

    def test_repository_registry_has_one_native_v1_profile(self) -> None:
        contracts = validate_registry(REGISTRY)
        self.assertEqual([item["isa_version"] for item in contracts], ["M64K-v1"])

    def test_cut_line_source_revision_must_match_manual_manifest(self) -> None:
        self.assert_cut_line_invalid(lambda item: item["sources"]["table_1_3"].update({"revision": "unknown"}))

    def test_cut_line_appendix_parent_must_exist(self) -> None:
        self.assert_cut_line_invalid(lambda item: item["appendix_c_fp_conditionals"][0].update({"parent_table_1_3_id": "missing"}))

    def test_cut_line_table_c4_requires_every_column(self) -> None:
        self.assert_cut_line_invalid(lambda item: item["appendix_c_operand_type_matrix"]["rows"][0]["statuses"].pop())

    def test_cut_line_cannot_close_with_incomplete_system_inventory(self) -> None:
        candidate = load_object(CUT_LINE)
        candidate["status"] = "approved"
        candidate["classification_status"] = "approved"
        for section_name in (
            "table_1_3_entries",
            "appendix_c_integer_variants",
            "appendix_c_fp_families",
            "appendix_c_fp_conditionals",
            "appendix_c_fp_effective_address_forms",
            "rejected_fp_formats",
        ):
            for row in candidate[section_name]:
                row["review_status"] = "approved"
        candidate["appendix_c_operand_type_matrix"]["review_status"] = "approved"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mc68060-semantic-cut-line.json"
            path.write_text(json.dumps(candidate), encoding="utf-8")
            _, approved = validate_cut_line_inventory(path, MANUAL_MANIFEST)
        self.assertFalse(approved)

    def test_unknown_top_level_field_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item.update({"compatibility_mode": "M68K"}))

    def test_semantic_contract_reference_is_mandatory(self) -> None:
        self.assert_invalid(lambda item: item.update({"semantic_contracts": []}))

    def test_unallocated_semantics_cannot_claim_encoding(self) -> None:
        self.assert_invalid(lambda item: item["semantic_contracts"][0].update({"encoding_status": "allocated"}))

    def test_integer_semantic_result_cannot_be_arbitrary_text(self) -> None:
        self.assert_semantic_invalid(0, lambda item: item["operations"][0].update({"result": "implementation-defined"}))

    def test_shift_semantic_carry_cannot_be_arbitrary_text(self) -> None:
        self.assert_semantic_invalid(1, lambda item: item["operations"][0].update({"carry": "whatever-the-test-observed"}))

    def test_semantic_citation_section_cannot_be_arbitrary_text(self) -> None:
        self.assert_semantic_invalid(0, lambda item: item["sources"][1].update({"section": "some manual section"}))

    def test_semantic_citation_pages_cannot_be_arbitrary_text(self) -> None:
        self.assert_semantic_invalid(1, lambda item: item["sources"][0].update({"pages": "unknown"}))

    def test_semantic_source_manifest_path_is_repository_bound(self) -> None:
        self.assert_semantic_invalid(0, lambda item: item["source_manifest"].update({"path": "/tmp/unreviewed-manifest.json"}))

    def test_semantic_source_must_exist_in_reviewed_manifest(self) -> None:
        self.assert_semantic_invalid(1, lambda item: item["sources"][0].update({"document_id": "UNREVIEWED"}))

    def test_semantic_schema_rejects_additional_contract_fields(self) -> None:
        self.assert_semantic_invalid(0, lambda item: item.update({"observed_test_answer": True}))

    def test_semantic_schema_definition_rejects_unknown_keywords(self) -> None:
        self.assert_semantic_invalid(0, lambda item: None, lambda schema: schema.update({"acceptAnything": True}))

    def test_multiply_divide_semantics_cannot_change_signed_rounding(self) -> None:
        self.assert_semantic_invalid(2, lambda item: item["division"].update({"signed_quotient_rounding": "floor"}))

    def test_multiply_divide_semantics_cannot_weaken_fault_priority(self) -> None:
        self.assert_semantic_invalid(2, lambda item: item["division"].update({"fault_priority": ["IntegerDivideOverflow", "IntegerDivideByZero"]}))

    def test_multiply_divide_semantics_cannot_publish_fault_writes(self) -> None:
        self.assert_semantic_invalid(2, lambda item: item["synchronous_exceptions"][0].update({"architectural_writes": "quotient"}))

    def test_multiply_divide_citations_are_strict(self) -> None:
        self.assert_semantic_invalid(2, lambda item: item["sources"][1].update({"pages": "approximately chapter four"}))

    def test_compatibility_banks_are_rejected(self) -> None:
        self.assert_invalid(lambda item: item["registers"].update({"banks": []}))

    def test_hardwired_zero_register_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["registers"]["general"].update({"zero_register": "r0"}))

    def test_writable_p0_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["registers"]["predicates"].update({"p0": "writable"}))

    def test_narrow_preserving_write_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["scalar_widths"]["general_register_write"].update({"L": "preserve-upper"}))

    def test_multi_instruction_pseudoinstruction_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["assembly"].update({"multi_instruction_pseudoinstructions": "permitted"}))

    def test_fma_is_mandatory(self) -> None:
        self.assert_invalid(lambda item: item["floating_point"].update({"fused_multiply_add": False}))

    def test_product_topology_is_four_cores_smt2(self) -> None:
        self.assert_invalid(lambda item: item["product_topology"].update({"hardware_threads_per_core": 1}))

    def test_product_target_width_cannot_drift(self) -> None:
        self.assert_invalid(lambda item: item["implementation_target"]["core"].update({"decode_instructions_per_cycle": 2}))

    def test_product_target_issue_capacity_cannot_drift(self) -> None:
        self.assert_invalid(lambda item: item["implementation_target"]["core"].update({"issue_uops_per_cycle": 4}))

    def test_product_target_rob_capacity_cannot_drift(self) -> None:
        self.assert_invalid(lambda item: item["implementation_target"]["core"].update({"rob_entries_per_core": 128}))

    def test_product_target_cannot_claim_implementation(self) -> None:
        self.assert_invalid(lambda item: item["implementation_target"].update({"implemented": True}))

    def test_deferred_vector_geometry_cannot_leak_into_base_interfaces(self) -> None:
        self.assert_invalid(lambda item: item["implementation_target"]["deferred_extensions"].update({"fixed-vector-length_or_tile_geometry_in_base_interfaces": "permitted"}))

    def test_non_fixed32_base_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["encoding"]["base_envelope"].update({"instruction_bits": 16}))

    def test_unassigned_extended_escape_must_remain_null(self) -> None:
        self.assert_invalid(lambda item: item["encoding"]["extended_envelope"].update({"escape_selector": {"value": 1}}))

    def test_empty_inventory_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"].update({"inventory": []}))

    def test_empty_ledger_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"].update({"ledger": []}))

    def test_inventory_without_ledger_row_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["ledger"].pop())

    def test_ledger_without_inventory_row_is_rejected(self) -> None:
        def mutate(item) -> None:
            row = copy.deepcopy(item["semantic_baseline"]["ledger"][0])
            row["baseline_id"] = "MC68060.undeclared"
            item["semantic_baseline"]["ledger"].append(row)
        self.assert_invalid(mutate)

    def test_duplicate_inventory_identity_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["inventory"].append(copy.deepcopy(item["semantic_baseline"]["inventory"][0])))

    def test_empty_m64k_mapping_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["ledger"][0].update({"m64k_contract_ids": []}))

    def test_unknown_lowering_strategy_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["ledger"][0].update({"lowering_strategy": "software-sequence"}))

    def test_alias_identity_is_independent_of_lowering(self) -> None:
        candidate = copy.deepcopy(self.contract)
        row = candidate["semantic_baseline"]["ledger"][0]
        row["architectural_identity"] = "one-to-one-alias"
        row["lowering_strategy"] = "microcode"
        validate_contract(candidate, "M64K-v1")

    def test_computational_analogue_policy_cannot_be_weakened(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["coverage_policy"].update({"computational_baseline_member": "optional"}))

    def test_alias_cannot_expand_to_multiple_instructions(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["coverage_policy"].update({"alias_expansion": "multiple-instructions"}))

    def test_missing_disposition_dimension_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["ledger"][0]["disposition"].pop("restart"))

    def test_empty_disposition_detail_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["ledger"][0]["disposition"]["widths"].update({"detail": ""}))

    def test_undeclared_manual_citation_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["ledger"][0]["sources"][0].update({"document_id": "unknown"}))

    def test_contract_source_digest_must_match_reviewed_manual_manifest(self) -> None:
        manifest = load_object(MANUAL_MANIFEST)
        manifest["documents"][0]["sha256"] = "0" * 64
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaises(ContractError):
                validate_source_manifest(self.contract, path)

    def test_incomplete_citation_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["ledger"][0]["sources"][0].pop("pages"))

    def test_incomplete_corpus_requires_blockers(self) -> None:
        self.assert_invalid(lambda item: item["semantic_baseline"]["corpus_closure"].update({"blockers": []}))

    def test_false_corpus_closure_claim_is_rejected(self) -> None:
        def mutate(item) -> None:
            item["semantic_baseline"]["corpus_closure"]["status"] = "closed"
            item["semantic_baseline"]["corpus_closure"]["blockers"] = []
        self.assert_invalid(mutate)

    def test_closed_computational_row_cannot_be_rejected(self) -> None:
        candidate = copy.deepcopy(self.contract)
        baseline = candidate["semantic_baseline"]
        baseline["inventory"] = [{"baseline_id": "MC68060.ADD", "kind": "instruction", "member_enumeration_complete": True}]
        row = copy.deepcopy(baseline["ledger"][0])
        row["baseline_id"] = "MC68060.ADD"
        row["lineage_disposition"] = "rejected"
        row["architectural_identity"] = "absent"
        row["lowering_strategy"] = "no-execution"
        row["review_status"] = "approved"
        baseline["ledger"] = [row]
        baseline["corpus_closure"]["status"] = "closed"
        baseline["corpus_closure"]["blockers"] = []
        with self.assertRaises(ContractError):
            validate_semantic_baseline(candidate)

    def test_closed_system_row_cannot_use_computational_mapping(self) -> None:
        candidate = copy.deepcopy(self.contract)
        baseline = candidate["semantic_baseline"]
        baseline["inventory"] = [{"baseline_id": "MC68060.RESET", "kind": "system", "member_enumeration_complete": True}]
        row = copy.deepcopy(baseline["ledger"][2])
        row["baseline_id"] = "MC68060.RESET"
        row["lineage_disposition"] = "native-analogue"
        row["architectural_identity"] = "distinct-instruction"
        row["lowering_strategy"] = "direct-uops"
        row["review_status"] = "approved"
        baseline["ledger"] = [row]
        baseline["corpus_closure"]["status"] = "closed"
        baseline["corpus_closure"]["blockers"] = []
        with self.assertRaises(ContractError):
            validate_semantic_baseline(candidate)

    def test_backend_cannot_claim_semantic_closure(self) -> None:
        self.assert_invalid(lambda item: item["backend_claims"].update({"semantic_inventory_closed": True}))

    def test_unfrozen_backend_claim_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["backend_claims"].update({"compiler_backend_ready": True}))

    def test_provisional_elf_machine_number_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["abi"].update({"elf_machine": 0xFEED}))

    def test_m68k_reset_domain_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["privilege"]["reset"].update({"execution_domain": "M68K"}))

    def test_lr_sc_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["atomics"]["operations"].append("load-reserved"))

    def test_calling_convention_drift_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["abi"]["calling_convention"].update({"stack_pointer": "r30"}))

    def test_endian_tlb_tag_is_rejected(self) -> None:
        self.assert_invalid(lambda item: item["mmu"]["tlb_tag_fields"].append("endian"))

    def test_physical_address_range_cannot_drop_below_36_bits(self) -> None:
        self.assert_invalid(lambda item: item["mmu"]["physical_address_bits"].update({"minimum": 32}))

    def test_first_product_physical_address_width_is_48_bits(self) -> None:
        self.assert_invalid(lambda item: item["mmu"]["physical_address_bits"].update({"first_product": 40}))


if __name__ == "__main__":
    unittest.main()
