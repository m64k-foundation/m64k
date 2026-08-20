#!/usr/bin/env python3
"""Validate the first-product outstanding-uop and completion contract."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
CONTRACT_PATH = Path("docs/m64k/contracts/outstanding-uop-completion-v1.json")
SCHEMA_PATH = Path("docs/m64k/contracts/outstanding-uop-completion-schema-v1.json")
LIFETIME_PATH = Path("docs/m64k/contracts/rob-allocation-lifetime-v1.json")
PRODUCT_PATH = Path("isa/native/m64k-native-v1.json")
ARCH_TYPES_PATH = Path("rtl/packages/m64k_arch_types_pkg.sv")
BACKEND_TYPES_PATH = Path("rtl/core/execute/common/m64k_execute_backend_pkg.sv")


class UopCompletionContractError(ValueError):
    """The outstanding-uop completion contract is incomplete or contradictory."""


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise UopCompletionContractError(f"{path}: cannot load JSON object: {error}") from error

    if not isinstance(value, dict):
        raise UopCompletionContractError(f"{path}: top level must be an object")

    return value


def require_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise UopCompletionContractError(f"{label}: expected {expected!r}, found {actual!r}")


def read_unsigned_parameter(path: Path, parameter_name: str) -> int:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as error:
        raise UopCompletionContractError(f"{path}: cannot read SystemVerilog contract: {error}") from error

    match = re.search(rf"\b{re.escape(parameter_name)}\s*=\s*(\d+)\b", source)
    if match is None:
        raise UopCompletionContractError(f"{path}: parameter {parameter_name} is absent or not an unsigned decimal constant")
    return int(match.group(1))


def audit_schema_strictness(schema: dict[str, Any], location: str = "schema") -> None:
    if schema.get("type") == "object":
        require_equal(schema.get("additionalProperties"), False, f"{location} additionalProperties")
        properties = schema.get("properties")
        required = schema.get("required")
        if not isinstance(properties, dict) or not isinstance(required, list):
            raise UopCompletionContractError(f"{location}: object schema requires properties and required lists")
        require_equal(set(required), set(properties), f"{location} required property closure")
        for property_name, property_schema in properties.items():
            if not isinstance(property_schema, dict):
                raise UopCompletionContractError(f"{location}.{property_name}: property schema must be an object")
            audit_schema_strictness(property_schema, f"{location}.{property_name}")


def validate_against_strict_schema(value: object, schema: dict[str, Any], location: str = "contract") -> None:
    if "const" in schema:
        require_equal(value, schema["const"], location)
        return

    schema_type = schema.get("type")
    if schema_type == "object":
        if not isinstance(value, dict):
            raise UopCompletionContractError(f"{location}: expected object, found {type(value).__name__}")
        properties = schema["properties"]
        required = schema["required"]
        missing = set(required).difference(value)
        extras = set(value).difference(properties)
        if missing:
            raise UopCompletionContractError(f"{location}: missing required fields {sorted(missing)}")
        if extras:
            raise UopCompletionContractError(f"{location}: unexpected fields {sorted(extras)}")
        for property_name, property_schema in properties.items():
            validate_against_strict_schema(value[property_name], property_schema, f"{location}.{property_name}")
        return

    raise UopCompletionContractError(f"{location}: unsupported non-constant schema node")


def validate_contract(repository_root: Path) -> None:
    contract = load_object(repository_root / CONTRACT_PATH)
    schema = load_object(repository_root / SCHEMA_PATH)
    lifetime = load_object(repository_root / LIFETIME_PATH)
    product = load_object(repository_root / PRODUCT_PATH)

    require_equal(schema.get("$schema"), "https://json-schema.org/draft/2020-12/schema", "schema dialect")
    require_equal(schema.get("$id"), "https://m64k.org/contracts/outstanding-uop-completion-schema-v1.json", "schema identity")
    audit_schema_strictness(schema)
    validate_against_strict_schema(contract, schema)

    topology = contract["topology"]
    identity = contract["identity"]
    separation = contract["ownership_separation"]
    membership = contract["membership"]
    completion = contract["completion"]
    squash = contract["squash_and_reset"]
    product_target = product["implementation_target"]
    product_core = product_target["core"]
    product_scalability = product_target["scalability"]
    lifetime_topology = lifetime["topology"]
    lifetime_identity = lifetime["identity"]

    require_equal(topology["product_cores"], product_scalability["cores"], "product core count")
    require_equal(topology["hardware_threads_per_core"], product_scalability["hardware_threads_per_core"], "SMT siblings")
    require_equal(topology["rob_entries_per_core"], product_core["rob_entries_per_core"], "ROB entries")
    require_equal(topology["registration_lanes"], product_core["issue_uops_per_cycle"], "registration bandwidth")
    require_equal(topology["seal_lanes"], product_core["decode_instructions_per_cycle"], "membership seal bandwidth")
    require_equal(topology["completion_lanes"], product_core["issue_uops_per_cycle"], "completion bandwidth")
    require_equal(topology["retirement_observation_lanes"], product_core["retire_instructions_per_cycle"], "retirement observation bandwidth")
    require_equal(topology["rob_entries_per_core"], lifetime_topology["entries"], "lifetime/completion ROB capacity")
    require_equal(topology["hardware_threads_per_core"], lifetime_topology["hardware_threads"], "lifetime/completion thread topology")
    require_equal(topology["completion_lanes"], lifetime_topology["validation_lanes"], "lifetime validation/completion bandwidth")

    require_equal(identity["lifetime_fields"], ["core-id", "hardware-thread-id", "rob-index", "rob-generation", "allocation-sequence"], "complete lifetime identity")
    require_equal(identity["uop_fields"], identity["lifetime_fields"] + ["uop-index"], "complete uop identity")
    require_equal(identity["allocation_sequence_bits"], lifetime_identity["allocation_sequence_bits"], "allocation sequence width")
    require_equal(identity["rob_generation_bits"], lifetime_identity["generation_bits"], "ROB generation width")
    require_equal(identity["core_id_bits"], read_unsigned_parameter(repository_root / ARCH_TYPES_PATH, "M64K_CORE_ID_WIDTH"), "RTL/completion core identity width")
    require_equal(identity["hardware_thread_id_bits"], read_unsigned_parameter(repository_root / ARCH_TYPES_PATH, "M64K_HARDWARE_THREAD_ID_WIDTH"), "RTL/completion hardware-thread identity width")
    require_equal(identity["rob_index_bits"], read_unsigned_parameter(repository_root / BACKEND_TYPES_PATH, "M64K_BACKEND_ROB_INDEX_WIDTH"), "RTL/completion ROB index width")
    require_equal(identity["rob_generation_bits"], read_unsigned_parameter(repository_root / BACKEND_TYPES_PATH, "M64K_BACKEND_ROB_GENERATION_WIDTH"), "RTL/completion ROB generation width")
    require_equal(identity["allocation_sequence_bits"], read_unsigned_parameter(repository_root / BACKEND_TYPES_PATH, "M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH"), "RTL/completion allocation sequence width")
    require_equal(identity["uop_index_bits"], read_unsigned_parameter(repository_root / BACKEND_TYPES_PATH, "M64K_BACKEND_UOP_INDEX_WIDTH"), "RTL/completion uop index width")
    require_equal(1 << identity["rob_index_bits"] >= topology["rob_entries_per_core"], True, "ROB index representability")
    require_equal(1 << identity["uop_index_bits"], topology["uops_per_allocation"], "uop index capacity")
    require_equal(identity["equality"], "exact-full-width-no-hash-or-truncation", "identity comparison")

    require_equal(separation["rob_lifetime"], "external-exact-prerequisite", "ROB lifetime ownership")
    require_equal(separation["uop_membership"], "registered-and-outstanding-in-this-tracker", "uop membership ownership")
    require_equal(separation["retirement"], "never-authorized-by-this-contract", "retirement separation")
    require_equal(completion["retirement_effect"], "none", "completion retirement effect")

    require_equal(membership["same_cycle_registration_completes"], False, "same-cycle registration visibility")
    require_equal(membership["data_roles"], ["LOW", "HIGH", "QUOTIENT", "REMAINDER"], "typed data roles")
    require_equal(membership["manifest_fields"], ["data-role-mask", "nzcv-valid", "x-valid", "allowed-fault-class-set"], "expected completion manifest")
    require_equal(membership["membership_closure"], "nonempty-explicit-seal-after-or-atomically-with-final-registration", "membership closure")
    require_equal(membership["uop_reuse"], "forbidden-until-enclosing-rob-lifetime-release-or-recovery", "duplicate-detection lifetime")

    required_acceptance = {
        "rob-lifetime-match",
        "registered-member",
        "outstanding-not-completed",
        "unique-completion-lane",
        "not-released-or-recovered",
        "exact-terminal-payload",
    }
    require_equal(set(completion["acceptance_requires"]), required_acceptance, "completion acceptance prerequisites")
    require_equal(completion["duplicate_completion"], "protocol-violation-with-no-state-change-or-publication", "duplicate completion rejection")
    require_equal(completion["result_role_uniqueness"], "each-selected-role-exactly-once", "result role uniqueness")
    require_equal(completion["fault_payload"], "one-registered-class-typed-fault-with-no-data-nzcv-or-x-publication", "fault/publication exclusion")
    require_equal(completion["publication"], "atomic-with-completion-acceptance", "publication atomicity")
    require_equal(completion["all_uops_complete"], "lifetime-match-and-nonempty-sealed-membership-and-every-member-completed", "completion evidence")

    require_equal(squash["release_and_recovery"], "dominate-registration-seal-completion-readiness-fault-and-publication", "squash dominance")
    require_equal(squash["reset"], "clear-valid-and-protocol-state-only", "reset state")
    require_equal(squash["payload_reset"], "forbidden-as-a-functional-requirement", "payload reset policy")

    required_formal = {
        "lifetime-prerequisite",
        "exact-uop-membership",
        "no-duplicate-completion",
        "manifest-exactness",
        "seal-closure",
        "atomic-terminal-event",
        "squash-atomicity",
        "sibling-and-core-isolation",
        "unused-index-rejection",
        "noninterference",
        "reset-hygiene",
        "retirement-separation",
    }
    require_equal(set(contract["formal_acceptance"]), required_formal, "formal acceptance closure")

    required_non_claims = {
        "rob-lifetime-storage",
        "instruction-ordering",
        "oldest-instruction-selection",
        "exception-priority",
        "architectural-retirement",
        "store-commitment",
        "branch-recovery-mask-generation",
        "physical-register-allocation",
        "execution-result-value-generation",
    }
    require_equal(set(contract["non_claims"]), required_non_claims, "ownership non-claims")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=REPOSITORY_ROOT)
    arguments = parser.parse_args(argv)

    try:
        validate_contract(arguments.repository_root.resolve())
    except (KeyError, TypeError, UopCompletionContractError) as error:
        print(f"Outstanding-uop completion contract error: {error}", file=sys.stderr)
        return 1

    print("M64K outstanding-uop completion contract valid: 4C2T, ROB192, 6-lane exact completion, typed publication, atomic squash, and retirement separation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
