#!/usr/bin/env python3
"""Validate the first-product ROB allocation-lifetime implementation contract."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
CONTRACT_PATH = Path("docs/m64k/contracts/rob-allocation-lifetime-v1.json")
SCHEMA_PATH = Path("docs/m64k/contracts/rob-allocation-lifetime-schema-v1.json")
PRODUCT_PATH = Path("isa/native/m64k-native-v1.json")


class LifetimeContractError(ValueError):
    """The ROB allocation-lifetime contract is incomplete or contradictory."""


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise LifetimeContractError(f"{path}: cannot load JSON object: {error}") from error
    if not isinstance(value, dict):
        raise LifetimeContractError(f"{path}: top level must be an object")
    return value


def require_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise LifetimeContractError(f"{label}: expected {expected!r}, found {actual!r}")


def audit_schema_strictness(schema: dict[str, Any], location: str = "schema") -> None:
    if schema.get("type") == "object":
        require_equal(schema.get("additionalProperties"), False, f"{location} additionalProperties")
        properties = schema.get("properties")
        required = schema.get("required")
        if not isinstance(properties, dict) or not isinstance(required, list):
            raise LifetimeContractError(f"{location}: object schema requires properties and required lists")
        require_equal(set(required), set(properties), f"{location} required property closure")
        for property_name, property_schema in properties.items():
            if not isinstance(property_schema, dict):
                raise LifetimeContractError(f"{location}.{property_name}: property schema must be an object")
            audit_schema_strictness(property_schema, f"{location}.{property_name}")


def validate_against_strict_schema(value: object, schema: dict[str, Any], location: str = "contract") -> None:
    if "const" in schema:
        require_equal(value, schema["const"], location)
        return

    schema_type = schema.get("type")
    if schema_type == "object":
        if not isinstance(value, dict):
            raise LifetimeContractError(f"{location}: expected object, found {type(value).__name__}")
        properties = schema["properties"]
        required = schema["required"]
        missing = set(required).difference(value)
        extras = set(value).difference(properties)
        if missing:
            raise LifetimeContractError(f"{location}: missing required fields {sorted(missing)}")
        if extras:
            raise LifetimeContractError(f"{location}: unexpected fields {sorted(extras)}")
        for property_name, property_schema in properties.items():
            validate_against_strict_schema(value[property_name], property_schema, f"{location}.{property_name}")
        return

    raise LifetimeContractError(f"{location}: unsupported non-constant schema node")


def validate_contract(repository_root: Path) -> None:
    contract = load_object(repository_root / CONTRACT_PATH)
    schema = load_object(repository_root / SCHEMA_PATH)
    product = load_object(repository_root / PRODUCT_PATH)

    require_equal(schema.get("$schema"), "https://json-schema.org/draft/2020-12/schema", "schema dialect")
    require_equal(schema.get("$id"), "https://m64k.org/contracts/rob-allocation-lifetime-schema-v1.json", "schema identity")
    audit_schema_strictness(schema)
    validate_against_strict_schema(contract, schema)
    topology = contract["topology"]
    identity = contract["identity"]
    cycle = contract["cycle_semantics"]
    non_claims = contract["non_claims"]
    product_target = product["implementation_target"]

    require_equal(contract["contract"], "m64k-rob-allocation-lifetime-v1", "contract identity")
    require_equal(contract["status"], "normative-first-product-implementation-contract", "contract status")
    require_equal(contract["software_visible"], False, "software visibility")
    require_equal(topology["scope"], "per-core-shared-by-smt-siblings", "table scope")
    require_equal(topology["entries"], product_target["core"]["rob_entries_per_core"], "ROB entries")
    require_equal(topology["hardware_threads"], product_target["scalability"]["hardware_threads_per_core"], "SMT siblings")
    require_equal(topology["allocation_lanes"], product_target["core"]["decode_instructions_per_cycle"], "allocation lanes")
    require_equal(topology["release_lanes"], product_target["core"]["retire_instructions_per_cycle"], "release lanes")
    require_equal(topology["validation_lanes"], product_target["core"]["issue_uops_per_cycle"], "validation lanes")
    require_equal(topology["recovery_mask_bits"], topology["entries"], "recovery mask coverage")

    require_equal(identity["stored_fields"], ["hardware-thread-id", "rob-generation", "allocation-sequence"], "stored identity")
    require_equal(identity["core_check"], "request-core-equals-local-core", "core isolation")
    require_equal(identity["index_check"], "0-through-191-only", "implemented-index bounds")
    require_equal(identity["generation_bits"], 8, "generation width")
    require_equal(identity["allocation_sequence_bits"], 64, "allocation sequence width")
    require_equal(identity["uop_membership_owner"], "separate-outstanding-uop-completion-tracker", "uop ownership boundary")
    require_equal(identity["rollover"], "stop-allocation-and-prove-all-tagged-holders-drained-before-reuse", "rollover safety")

    require_equal(cycle["validation_view"], "registered-current-state", "validation state view")
    require_equal(cycle["release_suppresses_match"], True, "release-time stale rejection")
    require_equal(cycle["recovery_suppresses_match"], True, "recovery-time stale rejection")
    require_equal(cycle["same_cycle_allocation_matches"], False, "same-cycle allocation visibility")
    require_equal(cycle["same_index_turnover"], "exact-release-then-distinct-allocation-at-edge", "same-index turnover")
    require_equal(cycle["recovery_dominance"], "clear-and-reject-same-index-allocation", "recovery dominance")
    require_equal(cycle["conflict_policy"], "protocol-violation-with-no-conflicting-index-update", "lane-conflict behavior")
    require_equal(cycle["reset"], "clear-live-bits-only", "reset behavior")

    required_non_claims = {
        "rob-payload",
        "instruction-ordering",
        "branch-checkpoint-generation",
        "exception-priority",
        "destination-readiness",
        "physical-register-writeback",
        "duplicate-completion-detection",
        "store-visibility",
        "retirement",
    }
    missing_non_claims = required_non_claims.difference(non_claims)
    if missing_non_claims:
        raise LifetimeContractError(f"non-claims omit ownership boundaries: {sorted(missing_non_claims)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=REPOSITORY_ROOT)
    arguments = parser.parse_args(argv)

    try:
        validate_contract(arguments.repository_root.resolve())
    except (KeyError, TypeError, LifetimeContractError) as error:
        print(f"ROB lifetime contract error: {error}", file=sys.stderr)
        return 1

    print("M64K ROB allocation-lifetime contract valid: 192 entries, 4 allocate, 4 release, 6 validate, SMT ownership, recovery, and safe rollover")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
