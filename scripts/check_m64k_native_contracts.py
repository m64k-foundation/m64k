#!/usr/bin/env python3
"""Validate the single native M64K-v1 contract and its closed release gates."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any


CONTRACT_SCHEMA = "m64k.native.contract/v2"
REGISTRY_SCHEMA = "m64k.native.registry/v2"
MANUAL_MANIFEST_SCHEMA = "m64k.reference-manual-manifest/v2"
PROFILE = "M64K-v1"
CONDITIONS = ["T", "F", "HI", "LS", "CC", "CS", "NE", "EQ", "VC", "VS", "PL", "MI", "GE", "LT", "GT", "LE"]
ATOMIC_OPERATIONS = ["compare-exchange", "swap", "fetch-add", "fetch-and", "fetch-or", "fetch-xor"]
MEMORY_ORDERS = ["relaxed", "acquire", "release", "acq_rel", "seq_cst"]
EXTENDED_SPACES = ["M64K-A", "M64K-FD", "M64K-V", "M64K-M", "FUTURE", "VENDOR"]
TLB_TAGS = ["asid", "virtual-page-number", "page-size", "global", "translation-generation"]
READINESS_FIELDS = [
    "semantic_inventory_closed",
    "encoding_frozen",
    "elf_abi_frozen",
    "assembler_ready",
    "disassembler_ready",
    "linker_ready",
    "compiler_backend_ready",
    "linux_uapi_ready",
    "rtl_decoder_ready",
    "backend_ready",
]
DISPOSITION_DIMENSIONS = {
    "encoding",
    "widths",
    "registers",
    "operands",
    "result",
    "flags_predicates",
    "exceptions",
    "restart",
    "memory",
    "privilege",
    "state_formats",
    "implementation",
}
RELATIONS = {"adopted", "modified", "rejected", "new", "not-applicable"}
REVIEW_STATES = {"inventory-required", "draft", "reviewed", "approved", "rejected"}
LINEAGE_DISPOSITIONS = {"native-analogue", "modern-system-replacement", "rejected", "new"}
ARCHITECTURAL_IDENTITIES = {"distinct-instruction", "one-to-one-alias", "system-facility", "absent", "unresolved"}
LOWERING_STRATEGIES = {"direct-uops", "microcode", "no-execution", "unresolved"}
SHA256 = re.compile(r"^[0-9a-f]{64}$")
CUT_LINE_SCHEMA = "m64k.mc68060-semantic-cut-line/v2"
CUT_LINE_CLASSIFICATIONS = {"direct", "microcoded", "one-to-one-alias", "modern-replacement", "rejected", "unclassified"}
CUT_LINE_FINAL_REVIEW_STATES = {"approved", "rejected"}
CONTRACT_FIELDS = {
    "schema",
    "isa_family",
    "isa_version",
    "profile_kind",
    "status",
    "semantic_contracts",
    "backend_claims",
    "registers",
    "scalar_widths",
    "assembly",
    "floating_point",
    "product_topology",
    "implementation_target",
    "encoding",
    "semantic_baseline",
    "conditions",
    "privilege",
    "atomics",
    "abi",
    "mmu",
    "cache",
}

SHIFT_OPERATION_IDS = ["ASL", "ASR", "LSL", "LSR", "ROL", "ROR", "ROXL", "ROXR"]
INTEGER_ALU_OPERATION_IDS = ["ADD", "SUB", "ADCX", "SBCX", "AND", "OR", "XOR", "NOT", "NEG", "NEGX", "CMP", "TST"]


class ContractError(ValueError):
    """A contract contradicts the approved M64K-v1 architecture or gate."""


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"{path}: cannot load JSON: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"{path}: top level must be an object")
    return value


def obj(parent: dict[str, Any], key: str, label: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise ContractError(f"{label}.{key}: object required")
    return value


def array(parent: dict[str, Any], key: str, label: str, *, nonempty: bool = False) -> list[Any]:
    value = parent.get(key)
    if not isinstance(value, list):
        raise ContractError(f"{label}.{key}: array required")
    if nonempty and not value:
        raise ContractError(f"{label}.{key}: empty arrays cannot satisfy this gate")
    return value


def equal(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise ContractError(f"{label}: expected {expected!r}, got {actual!r}")


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ContractError(f"{label}: non-empty text required")
    return value


JSON_SCHEMA_DRAFT = "https://json-schema.org/draft/2020-12/schema"
JSON_SCHEMA_KEYWORDS = {
    "$schema",
    "$id",
    "title",
    "type",
    "const",
    "enum",
    "properties",
    "required",
    "additionalProperties",
    "items",
    "prefixItems",
    "minItems",
    "maxItems",
    "uniqueItems",
    "minLength",
    "pattern",
}


def validate_json_schema_definition(schema: Any, label: str, *, root: bool = False) -> None:
    if not isinstance(schema, dict):
        raise ContractError(f"{label}: JSON Schema object required")
    unknown = set(schema) - JSON_SCHEMA_KEYWORDS
    if unknown:
        raise ContractError(f"{label}: unsupported JSON Schema keywords {sorted(unknown)}")
    if root:
        equal(schema.get("$schema"), JSON_SCHEMA_DRAFT, f"{label}.$schema")
        text(schema.get("$id"), f"{label}.$id")
        text(schema.get("title"), f"{label}.title")
    schema_type = schema.get("type")
    if schema_type is not None and schema_type not in {"object", "array", "string", "integer", "boolean", "null"}:
        raise ContractError(f"{label}.type: unsupported JSON type {schema_type!r}")
    properties = schema.get("properties")
    if properties is not None:
        if not isinstance(properties, dict):
            raise ContractError(f"{label}.properties: object required")
        for name, child in properties.items():
            validate_json_schema_definition(child, f"{label}.properties.{name}")
    required = schema.get("required")
    if required is not None:
        if not isinstance(required, list) or len(required) != len(set(required)) or any(not isinstance(name, str) or not name for name in required):
            raise ContractError(f"{label}.required: unique non-empty property names required")
        if not isinstance(properties, dict) or not set(required) <= set(properties):
            raise ContractError(f"{label}.required: every required name must have a property schema")
    additional = schema.get("additionalProperties")
    if additional is not None and not isinstance(additional, bool):
        validate_json_schema_definition(additional, f"{label}.additionalProperties")
    items = schema.get("items")
    if items is not None and not isinstance(items, bool):
        validate_json_schema_definition(items, f"{label}.items")
    prefix_items = schema.get("prefixItems")
    if prefix_items is not None:
        if not isinstance(prefix_items, list):
            raise ContractError(f"{label}.prefixItems: array required")
        for index, child in enumerate(prefix_items):
            validate_json_schema_definition(child, f"{label}.prefixItems[{index}]")
    pattern = schema.get("pattern")
    if pattern is not None:
        try:
            re.compile(pattern)
        except (TypeError, re.error) as error:
            raise ContractError(f"{label}.pattern: invalid regular expression: {error}") from error


def validate_json_schema_instance(value: Any, schema: dict[str, Any], label: str) -> None:
    if "const" in schema and value != schema["const"]:
        raise ContractError(f"{label}: value does not match the normative schema constant")
    if "enum" in schema and value not in schema["enum"]:
        raise ContractError(f"{label}: value is outside the schema enumeration")

    schema_type = schema.get("type")
    type_matches = {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
        None: True,
    }
    if not type_matches[schema_type]:
        raise ContractError(f"{label}: expected JSON type {schema_type}")

    if isinstance(value, dict):
        properties = schema.get("properties", {})
        missing = set(schema.get("required", [])) - set(value)
        if missing:
            raise ContractError(f"{label}: missing required properties {sorted(missing)}")
        if schema.get("additionalProperties") is False:
            extra = set(value) - set(properties)
            if extra:
                raise ContractError(f"{label}: additional properties forbidden: {sorted(extra)}")
        for name, child_schema in properties.items():
            if name in value:
                validate_json_schema_instance(value[name], child_schema, f"{label}.{name}")

    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise ContractError(f"{label}: too few array items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise ContractError(f"{label}: too many array items")
        if schema.get("uniqueItems"):
            canonical_items = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(canonical_items) != len(set(canonical_items)):
                raise ContractError(f"{label}: array items must be unique")
        prefix_items = schema.get("prefixItems", [])
        for index, child_schema in enumerate(prefix_items):
            if index < len(value):
                validate_json_schema_instance(value[index], child_schema, f"{label}[{index}]")
        items = schema.get("items")
        if items is False and len(value) > len(prefix_items):
            raise ContractError(f"{label}: additional array items forbidden")
        if isinstance(items, dict):
            for index in range(len(prefix_items), len(value)):
                validate_json_schema_instance(value[index], items, f"{label}[{index}]")

    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise ContractError(f"{label}: string is shorter than the schema minimum")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            raise ContractError(f"{label}: string does not match the schema pattern")


def validate_instruction_semantic_contract(
    semantics: dict[str, Any],
    reference: dict[str, Any],
    semantics_path: Path,
    schema_path: Path,
    manifest_path: Path,
    label: str,
) -> None:
    schema = load_object(schema_path)
    validate_json_schema_definition(schema, f"{label} schema", root=True)
    validate_json_schema_instance(semantics, schema, label)
    for field in ("schema", "contract_id", "status", "encoding_status"):
        equal(semantics.get(field), reference[field], f"{label}.{field}")

    source_manifest = obj(semantics, "source_manifest", label)
    equal(set(source_manifest), {"path", "schema"}, f"{label}.source_manifest fields")
    equal(source_manifest.get("schema"), MANUAL_MANIFEST_SCHEMA, f"{label}.source_manifest.schema")
    declared_manifest_path = (semantics_path.parent / text(source_manifest.get("path"), f"{label}.source_manifest.path")).resolve()
    equal(declared_manifest_path, manifest_path.resolve(), f"{label}.source_manifest.path")

    manifest = load_object(manifest_path)
    equal(manifest.get("schema"), MANUAL_MANIFEST_SCHEMA, "reference manual manifest schema")
    manifest_documents = array(manifest, "documents", "reference manual manifest", nonempty=True)
    manifest_ids = {document.get("document_id") for document in manifest_documents if isinstance(document, dict)}
    for index, source in enumerate(array(semantics, "sources", label, nonempty=True)):
        if not isinstance(source, dict):
            raise ContractError(f"{label}.sources[{index}]: object required")
        if source.get("document_id") not in manifest_ids:
            raise ContractError(f"{label}.sources[{index}].document_id: source is absent from the reviewed manual manifest")


def register_range(prefix: str, first: int, last: int) -> list[str]:
    return [f"{prefix}{number}" for number in range(first, last + 1)]


def validate_semantic_contracts(contract: dict[str, Any], contract_directory: Path, manifest_path: Path) -> None:
    references = array(contract, "semantic_contracts", PROFILE, nonempty=True)
    expected_references = [
        {"contract_id": "M64K-v1.scalar-integer-alu", "path": "semantics/scalar-integer-alu-v1.json", "validation_schema": "semantics/scalar-integer-alu-schema-v1.json", "schema": "m64k.native.instruction-semantics/v1", "status": "normative-draft", "encoding_status": "unallocated"},
        {"contract_id": "M64K-v1.scalar-shift-rotate", "path": "semantics/scalar-shift-rotate-v1.json", "validation_schema": "semantics/scalar-shift-rotate-schema-v1.json", "schema": "m64k.native.instruction-semantics/v1", "status": "normative-draft", "encoding_status": "unallocated"},
        {"contract_id": "M64K-v1.scalar-multiply-divide", "path": "semantics/scalar-multiply-divide-v1.json", "validation_schema": "semantics/scalar-multiply-divide-schema-v1.json", "schema": "m64k.native.instruction-semantics/v1", "status": "normative-draft", "encoding_status": "unallocated"},
    ]
    equal(references, expected_references, f"{PROFILE}.semantic_contracts")
    alu_reference = references[0]
    reference = references[1]
    multiply_divide_reference = references[2]

    multiply_divide_path = contract_directory / multiply_divide_reference["path"]
    validate_instruction_semantic_contract(
        load_object(multiply_divide_path),
        multiply_divide_reference,
        multiply_divide_path,
        contract_directory / multiply_divide_reference["validation_schema"],
        manifest_path,
        "scalar multiply/divide semantic contract",
    )

    semantics_path = contract_directory / reference["path"]
    semantics = load_object(semantics_path)
    validate_instruction_semantic_contract(
        semantics,
        reference,
        semantics_path,
        contract_directory / reference["validation_schema"],
        manifest_path,
        "scalar shift/rotate semantic contract",
    )
    required_fields = {
        "schema", "contract_id", "status", "encoding_status", "scope", "source_manifest", "sources", "operand_widths_bits", "count",
        "writeback", "operations", "condition_state", "memory", "privilege", "synchronous_exceptions", "retirement",
        "lineage_differences", "verification",
    }
    equal(set(semantics), required_fields, "scalar shift/rotate semantic contract fields")
    for field in ("schema", "contract_id", "status", "encoding_status"):
        equal(semantics.get(field), reference[field], f"scalar shift/rotate semantic contract {field}")
    text(semantics.get("scope"), "scalar shift/rotate semantic contract scope")
    equal(semantics.get("operand_widths_bits"), [8, 16, 32, 64], "scalar shift/rotate operand widths")
    equal(semantics.get("count"), {
        "source_bits": "low-6",
        "range": [0, 63],
        "shift_reduction": "none",
        "rotate_reduction": "modulo-operand-width",
        "rotate_extend_reduction": "modulo-operand-width-plus-one",
    }, "scalar shift/rotate count contract")
    equal(semantics.get("writeback"), "truncate-to-operand-width-then-zero-extend-to-64", "scalar shift/rotate writeback")
    equal(semantics.get("condition_state"), {
        "without_F": "preserve-NZCV",
        "with_F": {"N": "result[W-1]", "Z": "result[W-1:0] == 0", "V": "operation-overflow-rule", "C": "operation-carry-rule"},
        "X": "ROXL-and-ROXR-write-resulting-X-even-without-F; all-other-operations-preserve-X",
        "zero_is_sticky": False,
    }, "scalar shift/rotate condition-state contract")

    operations = array(semantics, "operations", "scalar shift/rotate semantic contract", nonempty=True)
    equal([operation.get("id") for operation in operations if isinstance(operation, dict)], SHIFT_OPERATION_IDS, "scalar shift/rotate operation identities")
    operation_fields = {"id", "class", "direction", "reads_x", "writes_x", "result", "overflow", "carry"}
    for index, operation in enumerate(operations):
        label = f"scalar shift/rotate operations[{index}]"
        if not isinstance(operation, dict) or set(operation) != operation_fields:
            raise ContractError(f"{label}: exact operation semantic fields required")
        for field in ("class", "direction", "result", "overflow", "carry"):
            text(operation.get(field), f"{label}.{field}")
        if not isinstance(operation.get("reads_x"), bool) or not isinstance(operation.get("writes_x"), bool):
            raise ContractError(f"{label}: reads_x and writes_x must be boolean")
        expects_x = operation["id"] in {"ROXL", "ROXR"}
        equal(operation["reads_x"], expects_x, f"{label}.reads_x")
        equal(operation["writes_x"], expects_x, f"{label}.writes_x")

    manifest = load_object(manifest_path)
    manifest_documents = array(manifest, "documents", "reference manual manifest", nonempty=True)
    manifest_ids = {document.get("document_id") for document in manifest_documents if isinstance(document, dict)}
    sources = array(semantics, "sources", "scalar shift/rotate semantic contract", nonempty=True)
    equal([source.get("document_id") for source in sources if isinstance(source, dict)], ["MC68060UM", "M68000PRM"], "scalar shift/rotate lineage source identities")
    for index, source in enumerate(sources):
        label = f"scalar shift/rotate sources[{index}]"
        if not isinstance(source, dict) or set(source) != {"document_id", "section", "pages", "lineage_role"}:
            raise ContractError(f"{label}: exact citation fields required")
        if source["document_id"] not in manifest_ids:
            raise ContractError(f"{label}.document_id: source is absent from the reviewed manual manifest")
        for field in ("section", "pages", "lineage_role"):
            text(source.get(field), f"{label}.{field}")

    equal(semantics.get("synchronous_exceptions"), [], "scalar shift/rotate synchronous exceptions")
    for field in ("memory", "privilege", "retirement"):
        text(semantics.get(field), f"scalar shift/rotate {field}")
    for field in ("lineage_differences", "verification"):
        values = array(semantics, field, "scalar shift/rotate semantic contract", nonempty=True)
        if len(values) != len(set(values)) or any(not isinstance(value, str) or not value.strip() for value in values):
            raise ContractError(f"scalar shift/rotate {field}: unique non-empty strings required")

    alu_semantics_path = contract_directory / alu_reference["path"]
    alu_semantics = load_object(alu_semantics_path)
    validate_instruction_semantic_contract(
        alu_semantics,
        alu_reference,
        alu_semantics_path,
        contract_directory / alu_reference["validation_schema"],
        manifest_path,
        "scalar integer ALU semantic contract",
    )
    alu_required_fields = {
        "schema", "contract_id", "status", "encoding_status", "scope", "source_manifest", "sources", "operand_widths_bits", "writeback",
        "binary_operand_order", "operations", "condition_state", "memory", "privilege", "synchronous_exceptions",
        "retirement", "lineage_differences", "verification",
    }
    equal(set(alu_semantics), alu_required_fields, "scalar integer ALU semantic contract fields")
    for field in ("schema", "contract_id", "status", "encoding_status"):
        equal(alu_semantics.get(field), alu_reference[field], f"scalar integer ALU semantic contract {field}")
    text(alu_semantics.get("scope"), "scalar integer ALU semantic contract scope")
    equal(alu_semantics.get("operand_widths_bits"), [8, 16, 32, 64], "scalar integer ALU operand widths")
    equal(alu_semantics.get("writeback"), "truncate-to-operand-width-then-zero-extend-to-64", "scalar integer ALU writeback")
    equal(alu_semantics.get("binary_operand_order"), "left-operation-right", "scalar integer ALU operand order")
    equal(alu_semantics.get("condition_state"), {
        "ordinary_without_F": "preserve-NZCV",
        "F_and_always_forms": {"N": "result[W-1]", "Z": "result[W-1:0] == 0", "V": "operation-overflow-rule", "C": "operation-carry-rule"},
        "X": "ADCX-SBCX-and-NEGX-write-resulting-carry-or-borrow; all-other-operations-preserve-X",
        "zero_is_sticky": False,
    }, "scalar integer ALU condition-state contract")

    alu_operations = array(alu_semantics, "operations", "scalar integer ALU semantic contract", nonempty=True)
    equal([operation.get("id") for operation in alu_operations if isinstance(operation, dict)], INTEGER_ALU_OPERATION_IDS, "scalar integer ALU operation identities")
    alu_operation_fields = {"id", "result", "destination", "reads_x", "writes_x", "flag_mode", "carry", "overflow"}
    for index, operation in enumerate(alu_operations):
        label = f"scalar integer ALU operations[{index}]"
        if not isinstance(operation, dict) or set(operation) != alu_operation_fields:
            raise ContractError(f"{label}: exact operation semantic fields required")
        for field in ("result", "destination", "flag_mode", "carry", "overflow"):
            text(operation.get(field), f"{label}.{field}")
        expects_x = operation["id"] in {"ADCX", "SBCX", "NEGX"}
        equal(operation.get("reads_x"), expects_x, f"{label}.reads_x")
        equal(operation.get("writes_x"), expects_x, f"{label}.writes_x")
        expected_destination = "none" if operation["id"] in {"CMP", "TST"} else "gpr"
        equal(operation.get("destination"), expected_destination, f"{label}.destination")
        expected_flag_mode = "always" if expected_destination == "none" else "optional-F"
        equal(operation.get("flag_mode"), expected_flag_mode, f"{label}.flag_mode")

    alu_sources = array(alu_semantics, "sources", "scalar integer ALU semantic contract", nonempty=True)
    equal([source.get("document_id") for source in alu_sources if isinstance(source, dict)], ["MC68060UM", "M68000PRM"], "scalar integer ALU lineage source identities")
    for index, source in enumerate(alu_sources):
        label = f"scalar integer ALU sources[{index}]"
        if not isinstance(source, dict) or set(source) != {"document_id", "section", "pages", "lineage_role"}:
            raise ContractError(f"{label}: exact citation fields required")
        if source["document_id"] not in manifest_ids:
            raise ContractError(f"{label}.document_id: source is absent from the reviewed manual manifest")
        for field in ("section", "pages", "lineage_role"):
            text(source.get(field), f"{label}.{field}")

    equal(alu_semantics.get("synchronous_exceptions"), [], "scalar integer ALU synchronous exceptions")
    for field in ("memory", "privilege", "retirement"):
        text(alu_semantics.get(field), f"scalar integer ALU {field}")
    for field in ("lineage_differences", "verification"):
        values = array(alu_semantics, field, "scalar integer ALU semantic contract", nonempty=True)
        if len(values) != len(set(values)) or any(not isinstance(value, str) or not value.strip() for value in values):
            raise ContractError(f"scalar integer ALU {field}: unique non-empty strings required")


def validate_cut_line_inventory(inventory_path: Path, manifest_path: Path) -> tuple[set[str], bool]:
    inventory = load_object(inventory_path)
    expected_top_level = {
        "schema", "status", "purpose", "coverage", "classification_status", "classification_definitions", "sources",
        "table_1_3_entries", "appendix_c_integer_variants", "appendix_c_fp_families", "appendix_c_fp_conditionals",
        "appendix_c_fp_effective_address_forms", "appendix_c_operand_type_matrix", "rejected_fp_formats",
    }
    equal(set(inventory), expected_top_level, "MC68060 semantic inventory fields")
    equal(inventory.get("schema"), CUT_LINE_SCHEMA, "MC68060 semantic inventory schema")
    if inventory.get("status") not in {"draft", "approved"}:
        raise ContractError("MC68060 semantic inventory status: draft or approved required")
    expected_classification_status = "approved" if inventory["status"] == "approved" else "proposed-until-row-review"
    equal(inventory.get("classification_status"), expected_classification_status, "MC68060 semantic inventory classification status")
    text(inventory.get("purpose"), "MC68060 semantic inventory purpose")
    coverage = obj(inventory, "coverage", "MC68060 semantic inventory")
    equal(set(coverage), {"instruction_name_inventory", "instruction_form_inventory", "system_contract_inventory", "semantic_dispositions"}, "MC68060 semantic inventory coverage fields")
    if coverage.get("instruction_name_inventory") not in {"incomplete", "complete-for-listed-source-tables"}:
        raise ContractError("MC68060 semantic inventory coverage.instruction_name_inventory: invalid state")
    if coverage.get("instruction_form_inventory") not in {"incomplete", "complete"}:
        raise ContractError("MC68060 semantic inventory coverage.instruction_form_inventory: invalid state")
    if coverage.get("system_contract_inventory") not in {"not-started", "incomplete", "complete"}:
        raise ContractError("MC68060 semantic inventory coverage.system_contract_inventory: invalid state")
    if coverage.get("semantic_dispositions") not in {"not-approved", "approved"}:
        raise ContractError("MC68060 semantic inventory coverage.semantic_dispositions: invalid state")

    definitions = obj(inventory, "classification_definitions", "MC68060 semantic inventory")
    equal(set(definitions), CUT_LINE_CLASSIFICATIONS, "MC68060 semantic inventory classification definitions")
    for name, definition in definitions.items():
        text(definition, f"MC68060 semantic inventory classification_definitions.{name}")

    manifest = load_object(manifest_path)
    equal(manifest.get("schema"), MANUAL_MANIFEST_SCHEMA, "reference manual manifest schema")
    manifest_by_id: dict[str, dict[str, Any]] = {}
    for index, document in enumerate(array(manifest, "documents", "reference manual manifest", nonempty=True)):
        label = f"reference manual manifest.documents[{index}]"
        if not isinstance(document, dict):
            raise ContractError(f"{label}: object required")
        document_id = text(document.get("document_id"), f"{label}.document_id")
        if document_id in manifest_by_id:
            raise ContractError(f"{label}.document_id: duplicate {document_id!r}")
        manifest_by_id[document_id] = document
    sources = obj(inventory, "sources", "MC68060 semantic inventory")
    equal(set(sources), {"table_1_3", "appendix_c_integer", "appendix_c_fp", "appendix_c_operand_types"}, "MC68060 semantic inventory sources")
    for source_name, source in sources.items():
        label = f"MC68060 semantic inventory.sources.{source_name}"
        if not isinstance(source, dict) or set(source) != {"document_id", "title", "revision", "section", "printed_pages", "sha256"}:
            raise ContractError(f"{label}: exact source identity and citation fields required")
        manifest_document = manifest_by_id.get(source.get("document_id"))
        if manifest_document is None:
            raise ContractError(f"{label}.document_id: absent from the reviewed manual manifest")
        for field in ("title", "revision", "sha256"):
            equal(source.get(field), manifest_document.get(field), f"{label}.{field}")
        text(source.get("section"), f"{label}.section")
        text(source.get("printed_pages"), f"{label}.printed_pages")

    section_contracts = {
        "table_1_3_entries": {"baseline_id", "category", "classification", "m64k_disposition", "review_status"},
        "appendix_c_integer_variants": {"baseline_id", "parent_table_1_3_id", "classification", "review_status"},
        "appendix_c_fp_families": {"baseline_id", "category", "classification", "m64k_disposition", "review_status"},
        "appendix_c_fp_conditionals": {"baseline_id", "parent_table_1_3_id", "manual_status", "review_status"},
        "appendix_c_fp_effective_address_forms": {"baseline_id", "parent_table_1_3_id", "manual_status", "review_status"},
        "rejected_fp_formats": {"baseline_id", "classification", "reason", "review_status"},
    }
    qualified_ids: set[str] = set()
    all_rows_final = True
    table_ids: set[str] = set()
    section_entries: dict[str, list[Any]] = {}
    for section_name, required_fields in section_contracts.items():
        entries = array(inventory, section_name, "MC68060 semantic inventory", nonempty=True)
        section_entries[section_name] = entries
        local_ids: set[str] = set()
        for index, entry in enumerate(entries):
            label = f"MC68060 semantic inventory.{section_name}[{index}]"
            if not isinstance(entry, dict) or set(entry) != required_fields:
                raise ContractError(f"{label}: exact row fields required")
            baseline_id = text(entry.get("baseline_id"), f"{label}.baseline_id")
            if baseline_id in local_ids:
                raise ContractError(f"{label}.baseline_id: duplicate {baseline_id!r}")
            local_ids.add(baseline_id)
            qualified_ids.add(f"{section_name}:{baseline_id}")
            if "classification" in entry and entry.get("classification") not in CUT_LINE_CLASSIFICATIONS:
                raise ContractError(f"{label}.classification: invalid proposed mapping")
            if entry.get("review_status") not in {"draft", "reviewed", "approved", "rejected"}:
                raise ContractError(f"{label}.review_status: invalid review state")
            all_rows_final &= entry["review_status"] in CUT_LINE_FINAL_REVIEW_STATES
        if section_name == "table_1_3_entries":
            table_ids = local_ids

    parent_sections = ("appendix_c_integer_variants", "appendix_c_fp_conditionals", "appendix_c_fp_effective_address_forms")
    for section_name in parent_sections:
        for index, entry in enumerate(section_entries[section_name]):
            if entry["parent_table_1_3_id"] not in table_ids:
                raise ContractError(f"MC68060 semantic inventory.{section_name}[{index}].parent_table_1_3_id: missing Table 1-3 parent")

    matrix = obj(inventory, "appendix_c_operand_type_matrix", "MC68060 semantic inventory")
    equal(set(matrix), {"columns", "rows", "review_status"}, "MC68060 semantic inventory.appendix_c_operand_type_matrix fields")
    columns = array(matrix, "columns", "MC68060 semantic inventory.appendix_c_operand_type_matrix", nonempty=True)
    equal(columns, ["sgl", "dbl", "ext", "dec", "byte", "word", "long"], "MC68060 semantic inventory Appendix C Table C-4 columns")
    rows = array(matrix, "rows", "MC68060 semantic inventory.appendix_c_operand_type_matrix", nonempty=True)
    equal([row.get("value_class") for row in rows if isinstance(row, dict)], ["normalized", "zero", "infinity", "nan", "denormalized", "unnormalized"], "MC68060 semantic inventory Appendix C Table C-4 value classes")
    allowed_manual_statuses = {"hardware-implemented", "software-package-handled", "not-applicable"}
    for index, row in enumerate(rows):
        label = f"MC68060 semantic inventory.appendix_c_operand_type_matrix.rows[{index}]"
        if not isinstance(row, dict) or set(row) != {"value_class", "statuses"}:
            raise ContractError(f"{label}: exact value_class/statuses fields required")
        statuses = array(row, "statuses", label)
        if len(statuses) != len(columns) or any(status not in allowed_manual_statuses for status in statuses):
            raise ContractError(f"{label}.statuses: one valid manual status per Table C-4 column required")
        for column in columns:
            qualified_ids.add(f"appendix_c_operand_type_matrix:{row['value_class']}:{column}")
    if matrix.get("review_status") not in {"draft", "reviewed", "approved", "rejected"}:
        raise ContractError("MC68060 semantic inventory.appendix_c_operand_type_matrix.review_status: invalid review state")
    all_rows_final &= matrix["review_status"] in CUT_LINE_FINAL_REVIEW_STATES

    coverage_complete = coverage == {
        "instruction_name_inventory": "complete-for-listed-source-tables",
        "instruction_form_inventory": "complete",
        "system_contract_inventory": "complete",
        "semantic_dispositions": "approved",
    }
    inventory_approved = inventory["status"] == "approved" and all_rows_final and coverage_complete
    return qualified_ids, inventory_approved


def validate_registers(contract: dict[str, Any]) -> None:
    registers = obj(contract, "registers", PROFILE)
    prohibited = {"banks", "compatibility_mapping", "data", "address"} & set(registers)
    if prohibited:
        raise ContractError(f"{PROFILE}.registers: compatibility-bank fields forbidden: {sorted(prohibited)}")
    equal(obj(registers, "general", f"{PROFILE}.registers"), {"names": "r0-r31", "count": 32, "width_bits": 64, "all_writable": True, "zero_register": None}, f"{PROFILE}.registers.general")
    equal(obj(registers, "floating_point", f"{PROFILE}.registers"), {"names": "f0-f31", "count": 32, "width_bits": 64, "formats": ["binary32", "binary64"]}, f"{PROFILE}.registers.floating_point")
    equal(obj(registers, "predicates", f"{PROFILE}.registers"), {"names": "p0-p7", "count": 8, "width_bits": 1, "p0": "hardwired-true-writes-ignored", "writable": "p1-p7", "state_scope": "per-hardware-thread"}, f"{PROFILE}.registers.predicates")
    equal(obj(registers, "program_counter", f"{PROFILE}.registers"), {"name": "PC", "width_bits": 64}, f"{PROFILE}.registers.program_counter")
    state = obj(registers, "condition_state", f"{PROFILE}.registers")
    equal(obj(state, "nzcv", f"{PROFILE}.registers.condition_state"), {"name": "NZCV", "bits_msb_to_lsb": ["N", "Z", "C", "V"], "packed_encoding": {"N": 3, "Z": 2, "C": 1, "V": 0}, "width_bits": 4}, f"{PROFILE}.registers.condition_state.nzcv")
    equal(obj(state, "extend", f"{PROFILE}.registers.condition_state"), {"name": "X", "width_bits": 1, "separate_from_carry": True, "state_scope": "per-hardware-thread", "modified_only_by": ["ADCX", "SBCX", "NEGX", "rotate-through-X"]}, f"{PROFILE}.registers.condition_state.extend")


def validate_widths(contract: dict[str, Any]) -> None:
    widths = obj(contract, "scalar_widths", PROFILE)
    equal(widths.get("address_bits"), 64, f"{PROFILE}.scalar_widths.address_bits")
    equal(widths.get("integer_operand_bits"), [8, 16, 32, 64], f"{PROFILE}.scalar_widths.integer_operand_bits")
    equal(widths.get("floating_operand_bits"), [32, 64], f"{PROFILE}.scalar_widths.floating_operand_bits")
    equal(widths.get("suffixes"), {"B": 8, "W": 16, "L": 32, "Q": 64, "S": 32, "D": 64}, f"{PROFILE}.scalar_widths.suffixes")
    expected_writes = {"B": "zero-extend-8-to-64", "W": "zero-extend-16-to-64", "L": "zero-extend-32-to-64", "Q": "replace-all-64", "explicit_sign_extend": "sign-extend-source-to-64"}
    equal(obj(widths, "general_register_write", f"{PROFILE}.scalar_widths"), expected_writes, f"{PROFILE}.scalar_widths.general_register_write")


def validate_native_profile_contracts(contract: dict[str, Any]) -> None:
    assembly = obj(contract, "assembly", PROFILE)
    equal(assembly, {
        "architectural_statement": "exactly-one-instruction",
        "multi_instruction_pseudoinstructions": "forbidden",
        "aliases": "one-to-one-encoding-only",
        "familiar_m68k_names": "permitted-only-when-m64k-semantics-are-explicitly-equivalent",
        "source_compatibility_claim": False,
    }, f"{PROFILE}.assembly")
    floating_point = obj(contract, "floating_point", PROFILE)
    equal(floating_point, {
        "required": True,
        "standard": "IEEE-754-2019",
        "formats": ["binary32", "binary64"],
        "fused_multiply_add": True,
        "extended_binary80": False,
        "packed_decimal": False,
    }, f"{PROFILE}.floating_point")
    topology = obj(contract, "product_topology", PROFILE)
    equal(topology, {
        "cores": 4,
        "hardware_threads_per_core": 2,
        "architectural_contexts": 8,
        "identity_contract": "core-hardware-thread-transaction-privilege-domain-address-space-explicit",
    }, f"{PROFILE}.product_topology")
    implementation_target = obj(contract, "implementation_target", PROFILE)
    equal(implementation_target, {
        "status": "design-target-not-implementation-claim",
        "implemented": False,
        "core": {
            "execution_model": "out-of-order",
            "decode_instructions_per_cycle": 4,
            "retire_instructions_per_cycle": 4,
            "issue_uops_per_cycle": 6,
            "rob_entries_per_core": 192,
            "rob_identity_requirement": "context-index-generation-allocation-sequence-uop",
            "precise_retirement": True,
        },
        "scalability": {
            "cores": 4,
            "hardware_threads_per_core": 2,
            "single_core_single_thread_is_validation_projection_only": True,
            "shared_structure_identity_requirement": "every-entry-and-response-retains-owning-core-and-hardware-thread",
        },
        "deferred_extensions": {
            "scalable_vector": "separate-versioned-extension-required",
            "matrix_tile": "separate-versioned-extension-required",
            "fixed-vector-length_or_tile_geometry_in_base_interfaces": "forbidden",
        },
    }, f"{PROFILE}.implementation_target")


def validate_encoding(contract: dict[str, Any]) -> bool:
    encoding = obj(contract, "encoding", PROFILE)
    equal(encoding.get("instruction_alignment_bytes"), 4, f"{PROFILE}.encoding.instruction_alignment_bytes")
    equal(encoding.get("instruction_byte_order"), "big-endian", f"{PROFILE}.encoding.instruction_byte_order")
    text(encoding.get("illegal_default"), f"{PROFILE}.encoding.illegal_default")
    base = obj(encoding, "base_envelope", f"{PROFILE}.encoding")
    for field, expected in (("name", "fixed32"), ("instruction_bits", 32), ("instruction_bytes", 4)):
        equal(base.get(field), expected, f"{PROFILE}.encoding.base_envelope.{field}")
    patterns = array(base, "opcode_patterns", f"{PROFILE}.encoding.base_envelope")
    layouts = array(base, "operand_field_layouts", f"{PROFILE}.encoding.base_envelope")
    if base.get("allocation_status") == "unfrozen":
        equal(patterns, [], f"{PROFILE}.encoding.base_envelope.opcode_patterns")
        equal(layouts, [], f"{PROFILE}.encoding.base_envelope.operand_field_layouts")
        frozen = False
    elif base.get("allocation_status") == "frozen":
        if not patterns or not layouts:
            raise ContractError(f"{PROFILE}.encoding.base_envelope: frozen allocation requires patterns and layouts")
        frozen = True
    else:
        raise ContractError(f"{PROFILE}.encoding.base_envelope.allocation_status: invalid state")
    extended = obj(encoding, "extended_envelope", f"{PROFILE}.encoding")
    for field, expected in (("name", "extended"), ("minimum_instruction_bytes", 8), ("maximum_instruction_bytes", 16), ("length_granule_bytes", 4), ("reserved_spaces", EXTENDED_SPACES)):
        equal(extended.get(field), expected, f"{PROFILE}.encoding.extended_envelope.{field}")
    extended_patterns = array(extended, "opcode_patterns", f"{PROFILE}.encoding.extended_envelope")
    if extended.get("status") == "reserved-unassigned":
        equal(extended.get("escape_selector"), None, f"{PROFILE}.encoding.extended_envelope.escape_selector")
        equal(extended_patterns, [], f"{PROFILE}.encoding.extended_envelope.opcode_patterns")
    elif extended.get("status") == "frozen":
        if not isinstance(extended.get("escape_selector"), dict) or not extended_patterns:
            raise ContractError(f"{PROFILE}.encoding.extended_envelope: frozen allocation requires an escape and patterns")
    else:
        raise ContractError(f"{PROFILE}.encoding.extended_envelope.status: invalid state")
    return frozen


def validate_semantic_baseline(
    contract: dict[str, Any],
    contract_directory: Path | None = None,
    manifest_path: Path | None = None,
) -> bool:
    repository_root = Path(__file__).resolve().parents[1]
    contract_directory = contract_directory or repository_root / "isa/native"
    manifest_path = manifest_path or repository_root / "references/manuals/manifest.json"
    baseline = obj(contract, "semantic_baseline", PROFILE)
    equal(baseline.get("compatibility_claim"), False, f"{PROFILE}.semantic_baseline.compatibility_claim")
    equal(baseline.get("cut_line"), "MC68060", f"{PROFILE}.semantic_baseline.cut_line")
    equal(baseline.get("closed_world"), True, f"{PROFILE}.semantic_baseline.closed_world")
    semantic_inventory = obj(baseline, "semantic_inventory", f"{PROFILE}.semantic_baseline")
    equal(semantic_inventory, {
        "path": "mc68060-semantic-cut-line.json",
        "schema": CUT_LINE_SCHEMA,
        "required_status_for_closure": "approved",
    }, f"{PROFILE}.semantic_baseline.semantic_inventory")
    cut_line_ids, cut_line_approved = validate_cut_line_inventory(contract_directory / semantic_inventory["path"], manifest_path)
    policy = obj(baseline, "coverage_policy", f"{PROFILE}.semantic_baseline")
    equal(policy, {
        "computational_baseline_member": "architectural-m64k-analogue-required",
        "architectural_statement": "exactly-one-instruction",
        "computational_lineage_dispositions": ["native-analogue"],
        "legacy_system_lineage_dispositions": ["modern-system-replacement", "rejected"],
        "architectural_identities": ["distinct-instruction", "one-to-one-alias", "system-facility", "absent", "unresolved"],
        "lowering_strategies": ["direct-uops", "microcode", "no-execution", "unresolved"],
        "microcode_visibility": "architecturally-invisible",
        "alias_expansion": "exactly-one-identical-encoding",
    }, f"{PROFILE}.semantic_baseline.coverage_policy")

    documents = array(baseline, "source_documents", f"{PROFILE}.semantic_baseline", nonempty=True)
    document_ids: set[str] = set()
    for index, document in enumerate(documents):
        label = f"{PROFILE}.semantic_baseline.source_documents[{index}]"
        if not isinstance(document, dict) or set(document) != {"document_id", "title", "revision", "sha256"}:
            raise ContractError(f"{label}: exact document identity fields required")
        document_id = text(document.get("document_id"), f"{label}.document_id")
        if document_id in document_ids:
            raise ContractError(f"{label}.document_id: duplicate {document_id!r}")
        document_ids.add(document_id)
        text(document.get("title"), f"{label}.title")
        text(document.get("revision"), f"{label}.revision")
        if not isinstance(document.get("sha256"), str) or SHA256.fullmatch(document["sha256"]) is None:
            raise ContractError(f"{label}.sha256: lowercase SHA-256 required")

    inventory = array(baseline, "inventory", f"{PROFILE}.semantic_baseline", nonempty=True)
    inventory_ids: set[str] = set()
    inventory_complete = True
    for index, item in enumerate(inventory):
        label = f"{PROFILE}.semantic_baseline.inventory[{index}]"
        if not isinstance(item, dict) or set(item) != {"baseline_id", "kind", "member_enumeration_complete"}:
            raise ContractError(f"{label}: exact inventory fields required")
        baseline_id = text(item.get("baseline_id"), f"{label}.baseline_id")
        if baseline_id in inventory_ids:
            raise ContractError(f"{label}.baseline_id: duplicate {baseline_id!r}")
        inventory_ids.add(baseline_id)
        if item.get("kind") not in {"instruction", "instruction-family", "instruction-corpus", "system", "system-corpus"}:
            raise ContractError(f"{label}.kind: invalid inventory kind")
        if not isinstance(item.get("member_enumeration_complete"), bool):
            raise ContractError(f"{label}.member_enumeration_complete: boolean required")
        inventory_complete &= item["member_enumeration_complete"]

    ledger = array(baseline, "ledger", f"{PROFILE}.semantic_baseline", nonempty=True)
    ledger_ids: set[str] = set()
    all_approved = True
    for index, entry in enumerate(ledger):
        label = f"{PROFILE}.semantic_baseline.ledger[{index}]"
        required = {"baseline_id", "m64k_contract_ids", "lineage_disposition", "architectural_identity", "lowering_strategy", "review_status", "sources", "disposition", "verification"}
        if not isinstance(entry, dict) or set(entry) != required:
            raise ContractError(f"{label}: exact ledger fields required")
        baseline_id = text(entry.get("baseline_id"), f"{label}.baseline_id")
        if baseline_id in ledger_ids:
            raise ContractError(f"{label}.baseline_id: duplicate ledger row {baseline_id!r}")
        ledger_ids.add(baseline_id)
        contract_ids = array(entry, "m64k_contract_ids", label, nonempty=True)
        if len(contract_ids) != len(set(contract_ids)) or any(not isinstance(value, str) or not value.strip() for value in contract_ids):
            raise ContractError(f"{label}.m64k_contract_ids: unique non-empty identities required")
        if entry.get("lineage_disposition") not in LINEAGE_DISPOSITIONS:
            raise ContractError(f"{label}.lineage_disposition: invalid lineage disposition")
        if entry.get("architectural_identity") not in ARCHITECTURAL_IDENTITIES:
            raise ContractError(f"{label}.architectural_identity: invalid architectural identity")
        if entry.get("lowering_strategy") not in LOWERING_STRATEGIES:
            raise ContractError(f"{label}.lowering_strategy: invalid lowering strategy")
        if entry.get("review_status") not in REVIEW_STATES:
            raise ContractError(f"{label}.review_status: invalid review state")
        all_approved &= entry["review_status"] in {"approved", "rejected"}
        citations = array(entry, "sources", label, nonempty=True)
        for citation_index, citation in enumerate(citations):
            citation_label = f"{label}.sources[{citation_index}]"
            if not isinstance(citation, dict) or set(citation) != {"document_id", "section", "pages"}:
                raise ContractError(f"{citation_label}: exact document/section/pages citation required")
            if citation.get("document_id") not in document_ids:
                raise ContractError(f"{citation_label}.document_id: undeclared source {citation.get('document_id')!r}")
            text(citation.get("section"), f"{citation_label}.section")
            text(citation.get("pages"), f"{citation_label}.pages")
        disposition = obj(entry, "disposition", label)
        equal(set(disposition), DISPOSITION_DIMENSIONS, f"{label}.disposition dimensions")
        for dimension_name, dimension in disposition.items():
            dimension_label = f"{label}.disposition.{dimension_name}"
            if not isinstance(dimension, dict) or set(dimension) != {"relation", "detail"}:
                raise ContractError(f"{dimension_label}: exact relation/detail fields required")
            if dimension.get("relation") not in RELATIONS:
                raise ContractError(f"{dimension_label}.relation: invalid relation")
            text(dimension.get("detail"), f"{dimension_label}.detail")
        verification = array(entry, "verification", label, nonempty=True)
        if len(verification) != len(set(verification)) or any(not isinstance(value, str) or not value.strip() for value in verification):
            raise ContractError(f"{label}.verification: unique non-empty evidence requirements required")

    equal(ledger_ids, inventory_ids, f"{PROFILE}.semantic_baseline inventory/ledger closed-world identity set")
    closure = obj(baseline, "corpus_closure", f"{PROFILE}.semantic_baseline")
    text(closure.get("required_granularity"), f"{PROFILE}.semantic_baseline.corpus_closure.required_granularity")
    blockers = array(closure, "blockers", f"{PROFILE}.semantic_baseline.corpus_closure")
    if closure.get("status") == "closed":
        if blockers:
            raise ContractError(f"{PROFILE}.semantic_baseline.corpus_closure: closed corpus cannot retain blockers")
        if not inventory_complete or not all_approved or not cut_line_approved:
            raise ContractError(f"{PROFILE}.semantic_baseline.corpus_closure: closure requires complete enumeration and approved/rejected rows")
        inventory_by_id = {item["baseline_id"]: item for item in inventory}
        ledger_by_id = {item["baseline_id"]: item for item in ledger}
        if any(item["kind"] in {"instruction-corpus", "system-corpus"} for item in inventory):
            raise ContractError(f"{PROFILE}.semantic_baseline.corpus_closure: aggregate corpus rows must be replaced before closure")
        equal(ledger_ids, cut_line_ids, f"{PROFILE}.semantic_baseline ledger/MC68060 cut-line identity set")
        for baseline_id, item in inventory_by_id.items():
            row = ledger_by_id[baseline_id]
            if item["kind"] in {"instruction", "instruction-family"}:
                if row["lineage_disposition"] != "native-analogue":
                    raise ContractError(f"{PROFILE}.semantic_baseline.ledger: computational row {baseline_id!r} requires a native analogue")
                if row["architectural_identity"] not in {"distinct-instruction", "one-to-one-alias"}:
                    raise ContractError(f"{PROFILE}.semantic_baseline.ledger: computational row {baseline_id!r} requires a resolved architectural identity")
                if row["lowering_strategy"] not in {"direct-uops", "microcode"}:
                    raise ContractError(f"{PROFILE}.semantic_baseline.ledger: computational row {baseline_id!r} requires a resolved lowering strategy")
            if item["kind"] == "system":
                if row["lineage_disposition"] not in {"modern-system-replacement", "rejected"}:
                    raise ContractError(f"{PROFILE}.semantic_baseline.ledger: legacy system row {baseline_id!r} requires a modern replacement or explicit rejection")
                expected_identity = "system-facility" if row["lineage_disposition"] == "modern-system-replacement" else "absent"
                expected_lowering = "direct-uops" if row["lineage_disposition"] == "modern-system-replacement" else "no-execution"
                equal(row["architectural_identity"], expected_identity, f"{PROFILE}.semantic_baseline.ledger.{baseline_id}.architectural_identity")
                if row["lineage_disposition"] == "rejected":
                    equal(row["lowering_strategy"], expected_lowering, f"{PROFILE}.semantic_baseline.ledger.{baseline_id}.lowering_strategy")
        return True
    if closure.get("status") == "incomplete":
        if not blockers:
            raise ContractError(f"{PROFILE}.semantic_baseline.corpus_closure: incomplete corpus requires explicit blockers")
        return False
    raise ContractError(f"{PROFILE}.semantic_baseline.corpus_closure.status: incomplete or closed required")


def validate_source_manifest(contract: dict[str, Any], manifest_path: Path) -> None:
    manifest = load_object(manifest_path)
    equal(manifest.get("schema"), MANUAL_MANIFEST_SCHEMA, "reference manual manifest schema")
    manifest_documents = array(manifest, "documents", "reference manual manifest", nonempty=True)
    by_id: dict[str, dict[str, Any]] = {}
    for index, document in enumerate(manifest_documents):
        label = f"reference manual manifest.documents[{index}]"
        if not isinstance(document, dict):
            raise ContractError(f"{label}: object required")
        document_id = text(document.get("document_id"), f"{label}.document_id")
        if document_id in by_id:
            raise ContractError(f"{label}.document_id: duplicate {document_id!r}")
        by_id[document_id] = document

    source_documents = obj(contract, "semantic_baseline", PROFILE)["source_documents"]
    for index, source in enumerate(source_documents):
        label = f"{PROFILE}.semantic_baseline.source_documents[{index}]"
        manifest_document = by_id.get(source["document_id"])
        if manifest_document is None:
            raise ContractError(f"{label}.document_id: absent from the reviewed manual manifest")
        equal(source["title"], manifest_document.get("title"), f"{label}.title")
        equal(source["revision"], manifest_document.get("revision"), f"{label}.revision")
        equal(source["sha256"], manifest_document.get("sha256"), f"{label}.sha256")


def validate_conditions(contract: dict[str, Any]) -> None:
    conditions = array(contract, "conditions", PROFILE)
    if len(conditions) != 16 or any(not isinstance(item, dict) for item in conditions):
        raise ContractError(f"{PROFILE}.conditions: sixteen condition objects required")
    equal([item.get("code") for item in conditions], list(range(16)), f"{PROFILE}.conditions.codes")
    equal([item.get("name") for item in conditions], CONDITIONS, f"{PROFILE}.conditions.names")
    for index, item in enumerate(conditions):
        text(item.get("expression"), f"{PROFILE}.conditions[{index}].expression")


def validate_privilege_atomics(contract: dict[str, Any]) -> None:
    privilege = obj(contract, "privilege", PROFILE)
    equal(privilege.get("levels"), [{"id": "U", "name": "user", "rank": 0}, {"id": "S", "name": "supervisor", "rank": 1}, {"id": "M", "name": "machine", "rank": 2}], f"{PROFILE}.privilege.levels")
    equal(privilege.get("reserved_levels"), [{"id": "H", "name": "hypervisor", "status": "reserved-unimplemented"}], f"{PROFILE}.privilege.reserved_levels")
    equal(privilege.get("reset"), {"execution_domain": "native", "privilege": "M", "translation_enabled": False, "interrupts_enabled": False}, f"{PROFILE}.privilege.reset")
    equal(privilege.get("csr_access"), {"unknown_or_reserved": "IllegalInstruction", "insufficient_privilege": "PrivilegeViolation", "write_validation": "before-state-mutation", "commit": "precise-retirement-only"}, f"{PROFILE}.privilege.csr_access")
    atomics = obj(contract, "atomics", PROFILE)
    expected = {"required": True, "memory_model": "TSO", "operations": ATOMIC_OPERATIONS, "operand_bits": [8, 16, 32, 64], "orders": MEMORY_ORDERS, "lr_sc_supported": False, "alignment": "natural-required", "cacheability": "coherent-normal-memory-only", "must_not_cross_cache_line_bytes": 64, "fault_atomicity": "no-partial-memory-effect"}
    equal(atomics, expected, f"{PROFILE}.atomics")


def validate_abi_mmu_cache(contract: dict[str, Any]) -> bool:
    abi = obj(contract, "abi", PROFILE)
    expected_scalars = {"applicability": "required", "status": "draft-not-frozen", "identity": "M64K-v1-LP64D-BE", "data_model": "LP64D", "endianness": "big", "stack_alignment_bytes": 16, "elf_class": "ELFCLASS64", "elf_data": "ELFDATA2MSB", "elf_machine": "pending-official-EM_M64K-assignment", "relocation_format": "RELA", "relocation_numbers": "unassigned"}
    for field, expected in expected_scalars.items():
        equal(abi.get(field), expected, f"{PROFILE}.abi.{field}")
    equal(abi.get("integer_widths"), {"char": 8, "short": 16, "int": 32, "long": 64, "long_long": 64, "pointer": 64}, f"{PROFILE}.abi.integer_widths")
    equal(abi.get("floating_widths"), {"float": 32, "double": 64}, f"{PROFILE}.abi.floating_widths")
    convention = obj(abi, "calling_convention", f"{PROFILE}.abi")
    equal(convention.get("integer_arguments"), register_range("r", 0, 7), f"{PROFILE}.abi.integer_arguments")
    equal(convention.get("integer_returns"), ["r0", "r1"], f"{PROFILE}.abi.integer_returns")
    equal(convention.get("caller_saved"), register_range("r", 0, 17), f"{PROFILE}.abi.caller_saved")
    equal(convention.get("callee_saved"), register_range("r", 18, 27), f"{PROFILE}.abi.callee_saved")
    for field, expected in (("thread_pointer", "r28"), ("frame_pointer", "r29"), ("link_register", "r30"), ("stack_pointer", "r31")):
        equal(convention.get(field), expected, f"{PROFILE}.abi.{field}")
    equal(convention.get("floating_arguments"), register_range("f", 0, 7), f"{PROFILE}.abi.floating_arguments")
    equal(convention.get("floating_returns"), ["f0", "f1"], f"{PROFILE}.abi.floating_returns")
    equal(convention.get("floating_caller_saved"), register_range("f", 0, 15), f"{PROFILE}.abi.floating_caller_saved")
    equal(convention.get("floating_callee_saved"), register_range("f", 16, 31), f"{PROFILE}.abi.floating_callee_saved")
    aggregate = obj(abi, "aggregate_calling", f"{PROFILE}.abi")
    equal(aggregate, {"non_hfa_register_limit_bytes": 16, "non_hfa_register_slots": ["r0", "r1"], "hfa_member_formats": ["binary32", "binary64"], "hfa_member_count_minimum": 1, "hfa_member_count_maximum": 4, "hfa_registers": ["f0", "f1", "f2", "f3"], "sret_threshold_bits": 128, "sret_pointer": "r0", "sret_shifts_explicit_integer_arguments_to": "r1"}, f"{PROFILE}.abi.aggregate_calling")
    varargs = obj(abi, "varargs", f"{PROFILE}.abi")
    expected_varargs = {"register_save_area_bytes": 128, "general_save_area": {"offset_bytes": 0, "size_bytes": 64, "registers": register_range("r", 0, 7)}, "floating_save_area": {"offset_bytes": 64, "size_bytes": 64, "registers": register_range("f", 0, 7)}, "va_list_fields": ["general-register-offset", "floating-register-offset", "overflow-stack-pointer", "register-save-area-pointer"], "unnamed_fp_classification": "floating-register-save-area"}
    equal(varargs, expected_varargs, f"{PROFILE}.abi.varargs")

    mmu = obj(contract, "mmu", PROFILE)
    equal(mmu, {"translation_required": True, "virtual_address_bits": 48, "physical_address_bits": {"minimum": 36, "maximum": 48, "first_product": 48, "discovery": "implementation-csr"}, "canonical_rule": "bits-63:48-equal-bit-47", "asid_bits": 16, "page_table": {"levels": 4, "entry_bits": 64, "entries_per_level": 512, "page_sizes_bytes": [4096, 2097152, 1073741824]}, "tlb_tag_fields": TLB_TAGS}, f"{PROFILE}.mmu")
    cache = obj(contract, "cache", PROFILE)
    equal(obj(cache, "architectural", f"{PROFILE}.cache"), {"line_bytes": 64, "memory_order": "TSO"}, f"{PROFILE}.cache.architectural")
    equal(cache.get("hierarchy_required"), True, f"{PROFILE}.cache.hierarchy_required")
    profile = obj(cache, "implementation_profile", f"{PROFILE}.cache")
    equal((profile["l1i"].get("capacity_kib_per_core"), profile["l1i"].get("ways")), (32, 8), f"{PROFILE}.cache.l1i")
    equal((profile["l1d"].get("capacity_kib_per_core"), profile["l1d"].get("ways")), (32, 8), f"{PROFILE}.cache.l1d")
    equal((profile["l2"].get("capacity_kib_per_core"), profile["l2"].get("ways")), (512, 8), f"{PROFILE}.cache.l2")
    equal((profile["l3"].get("capacity_mib_total"), profile["l3"].get("ways"), profile["l3"].get("banks")), (4, 8, 8), f"{PROFILE}.cache.l3")
    return abi.get("status") == "frozen" and isinstance(abi.get("elf_machine"), int) and abi.get("relocation_numbers") != "unassigned"


def validate_readiness(contract: dict[str, Any], semantic_closed: bool, encoding_frozen: bool, abi_frozen: bool) -> None:
    claims = obj(contract, "backend_claims", PROFILE)
    if any(not isinstance(claims.get(field), bool) for field in READINESS_FIELDS):
        raise ContractError(f"{PROFILE}.backend_claims: every readiness field must be boolean")
    blockers = array(claims, "blockers", f"{PROFILE}.backend_claims")
    equal(claims["semantic_inventory_closed"], semantic_closed, f"{PROFILE}.backend_claims.semantic_inventory_closed")
    equal(claims["encoding_frozen"], encoding_frozen, f"{PROFILE}.backend_claims.encoding_frozen")
    equal(claims["elf_abi_frozen"], abi_frozen, f"{PROFILE}.backend_claims.elf_abi_frozen")
    foundations = semantic_closed and encoding_frozen and abi_frozen
    downstream = ["assembler_ready", "disassembler_ready", "linker_ready", "compiler_backend_ready", "linux_uapi_ready", "rtl_decoder_ready"]
    if not foundations and any(claims[field] for field in downstream + ["backend_ready"]):
        raise ContractError(f"{PROFILE}.backend_claims: downstream readiness is illegal before semantic, encoding, and ELF/ABI freeze")
    if claims["backend_ready"] and not all(claims[field] for field in downstream):
        raise ContractError(f"{PROFILE}.backend_claims: backend_ready requires every backend and RTL evidence gate")
    if claims["backend_ready"] and blockers:
        raise ContractError(f"{PROFILE}.backend_claims: a ready backend cannot retain blockers")
    if not claims["backend_ready"] and not blockers:
        raise ContractError(f"{PROFILE}.backend_claims: a closed readiness gate requires explicit blockers")


def validate_contract(
    contract: dict[str, Any],
    expected_version: str | None = None,
    contract_directory: Path | None = None,
    manifest_path: Path | None = None,
) -> None:
    equal(set(contract), CONTRACT_FIELDS, f"{PROFILE} top-level fields")
    equal(contract.get("schema"), CONTRACT_SCHEMA, f"{PROFILE}.schema")
    equal(contract.get("isa_family"), "M64K-native", f"{PROFILE}.isa_family")
    equal(contract.get("isa_version"), expected_version or PROFILE, f"{PROFILE}.isa_version")
    equal(contract.get("profile_kind"), "native-64-system-profile", f"{PROFILE}.profile_kind")
    repository_root = Path(__file__).resolve().parents[1]
    resolved_contract_directory = contract_directory or repository_root / "isa/native"
    resolved_manifest_path = manifest_path or repository_root / "references/manuals/manifest.json"
    validate_semantic_contracts(contract, resolved_contract_directory, resolved_manifest_path)
    validate_registers(contract)
    validate_widths(contract)
    validate_native_profile_contracts(contract)
    encoding_frozen = validate_encoding(contract)
    semantic_closed = validate_semantic_baseline(contract, contract_directory, manifest_path)
    validate_conditions(contract)
    validate_privilege_atomics(contract)
    abi_frozen = validate_abi_mmu_cache(contract)
    validate_readiness(contract, semantic_closed, encoding_frozen, abi_frozen)


def validate_registry(path: Path) -> list[dict[str, Any]]:
    registry = load_object(path)
    equal(set(registry), {"schema", "family", "contract_schema", "public_profiles", "release_gate"}, "registry fields")
    equal(registry.get("schema"), REGISTRY_SCHEMA, "registry.schema")
    equal(registry.get("family"), "M64K-native", "registry.family")
    equal(registry.get("contract_schema"), CONTRACT_SCHEMA, "registry.contract_schema")
    profiles = array(registry, "public_profiles", "registry", nonempty=True)
    if len(profiles) != 1 or not isinstance(profiles[0], dict):
        raise ContractError("registry.public_profiles: exactly one M64K-v1 profile required")
    equal(profiles[0].get("version"), PROFILE, "registry.public_profiles[0].version")
    equal(profiles[0].get("status"), "development", "registry.public_profiles[0].status")
    contract = load_object(path.parent / text(profiles[0].get("path"), "registry.public_profiles[0].path"))
    manifest_path = path.parents[2] / "references/manuals/manifest.json"
    validate_contract(contract, PROFILE, path.parent, manifest_path)
    validate_source_manifest(contract, manifest_path)
    gate = obj(registry, "release_gate", "registry")
    equal(gate.get("status"), "closed", "registry.release_gate.status")
    equal(gate.get("backend_ready"), False, "registry.release_gate.backend_ready")
    array(gate, "blocking_decisions", "registry.release_gate", nonempty=True)
    rule = text(gate.get("semantic_rule"), "registry.release_gate.semantic_rule")
    if "native 64-bit" not in rule or "never a binary" not in rule:
        raise ContractError("registry.release_gate.semantic_rule: native-64 and non-compatibility rule required")
    if gate["backend_ready"] != contract["backend_claims"]["backend_ready"]:
        raise ContractError("registry.release_gate.backend_ready: must match the sole public profile")
    return [contract]


def main() -> int:
    default = Path(__file__).resolve().parents[1] / "isa/native/registry.json"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("registry", nargs="?", type=Path, default=default)
    parser.add_argument("--require-backend-ready", action="store_true")
    args = parser.parse_args()
    try:
        contracts = validate_registry(args.registry)
    except (ContractError, KeyError, TypeError) as error:
        print(f"native ISA contract error: {error}", file=sys.stderr)
        return 2
    ready = contracts[0]["backend_claims"]["backend_ready"]
    print(f"M64K native contract valid: M64K-v1 native64 LP64D; semantic_corpus=incomplete; fixed32 allocation=unfrozen; backend_ready={str(ready).lower()}")
    if args.require_backend_ready and not ready:
        print("native ISA backend readiness gate is closed: semantic inventory, opcode allocation, and ELF/RELA allocation remain unfrozen", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
