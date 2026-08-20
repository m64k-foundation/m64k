#!/usr/bin/env python3
"""Check that stable RTL contracts can represent the first-product target."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


class AlignmentError(ValueError):
    """A stable RTL contract cannot represent the declared product target."""


def read_text(repository_root: Path, relative_path: str) -> str:
    path = repository_root / relative_path
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise AlignmentError(f"{relative_path}: cannot read required contract: {error}") from error


def unsigned_parameter(source: str, name: str, label: str) -> int:
    pattern = rf"\blocalparam\s+int\s+unsigned\s+{re.escape(name)}\s*=\s*(\d+)\s*;"
    match = re.search(pattern, source)
    if match is None:
        raise AlignmentError(f"{label}: unsigned localparam {name} is missing or is not a literal")
    return int(match.group(1))


def interface_parameter(source: str, name: str, label: str) -> int:
    pattern = rf"\bparameter\s+int\s+unsigned\s+{re.escape(name)}\s*=\s*(\d+)\b"
    match = re.search(pattern, source)
    if match is None:
        raise AlignmentError(f"{label}: interface parameter {name} is missing or is not a literal")
    return int(match.group(1))


def require_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise AlignmentError(f"{label}: expected {expected!r}, found {actual!r}")


def require_member(source: str, member: str, label: str) -> None:
    if re.search(rf"\b{re.escape(member)}\s*;", source) is None:
        raise AlignmentError(f"{label}: required identity member {member!r} is absent")


def validate_alignment(repository_root: Path) -> None:
    contract_path = repository_root / "isa/native/m64k-native-v1.json"
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AlignmentError(f"isa/native/m64k-native-v1.json: cannot load product contract: {error}") from error

    target = contract["implementation_target"]
    topology = target["scalability"]
    core_target = target["core"]
    physical_widths = contract["mmu"]["physical_address_bits"]

    arch_types = read_text(repository_root, "rtl/packages/m64k_arch_types_pkg.sv")
    backend_types = read_text(repository_root, "rtl/core/execute/common/m64k_execute_backend_pkg.sv")
    retirement_interface = read_text(repository_root, "rtl/interfaces/retirement/m64k_precise_retirement_if.sv")

    require_equal(unsigned_parameter(arch_types, "M64K_NATIVE_XLEN", "architecture types"), 64, "native integer width")
    require_equal(unsigned_parameter(arch_types, "M64K_INITIAL_CORE_COUNT", "architecture types"), topology["cores"], "initial core count")
    require_equal(unsigned_parameter(arch_types, "M64K_INITIAL_THREADS_PER_CORE", "architecture types"), topology["hardware_threads_per_core"], "initial hardware-thread count")
    require_equal(unsigned_parameter(arch_types, "M64K_VIRTUAL_ADDRESS_WIDTH", "architecture types"), 64, "virtual-address carrier width")
    require_equal(unsigned_parameter(arch_types, "M64K_PHYSICAL_ADDRESS_WIDTH", "architecture types"), physical_widths["maximum"], "physical-address carrier width")

    core_id_width = unsigned_parameter(arch_types, "M64K_CORE_ID_WIDTH", "architecture types")
    thread_id_width = unsigned_parameter(arch_types, "M64K_HARDWARE_THREAD_ID_WIDTH", "architecture types")
    require_equal(core_id_width, 6, "execution core identity width")
    require_equal(thread_id_width, 2, "execution hardware-thread identity width")
    if (1 << core_id_width) < topology["cores"]:
        raise AlignmentError("core identity width cannot represent every first-product core")
    if (1 << thread_id_width) < topology["hardware_threads_per_core"]:
        raise AlignmentError("hardware-thread identity width cannot represent every first-product sibling")

    rob_index_width = unsigned_parameter(backend_types, "M64K_BACKEND_ROB_INDEX_WIDTH", "execute backend types")
    required_rob_index_width = math.ceil(math.log2(core_target["rob_entries_per_core"]))
    if rob_index_width < required_rob_index_width:
        raise AlignmentError(f"ROB index width {rob_index_width} cannot represent {core_target['rob_entries_per_core']} entries")

    require_equal(unsigned_parameter(backend_types, "M64K_BACKEND_ROB_GENERATION_WIDTH", "execute backend types"), 8, "ROB generation width")
    require_equal(unsigned_parameter(backend_types, "M64K_BACKEND_UOP_INDEX_WIDTH", "execute backend types"), 4, "uop identity width")

    require_equal(
        unsigned_parameter(backend_types, "M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH", "execute backend types"),
        64,
        "allocation-lifetime sequence width",
    )

    tag_match = re.search(r"typedef\s+struct\s+packed\s*\{(?P<body>.*?)\}\s*m64k_execute_tag_t\s*;", backend_types, re.DOTALL)
    if tag_match is None:
        raise AlignmentError("execute tag: m64k_execute_tag_t packed structure is absent")
    for member in ("execution_context", "rob_index", "rob_generation", "allocation_sequence", "uop_index"):
        require_member(tag_match.group("body"), member, "execute tag")

    retire_lanes = interface_parameter(retirement_interface, "RETIRE_LANES", "retirement interface")
    require_equal(retire_lanes, core_target["retire_instructions_per_cycle"], "default retirement lanes")

    base_contract_sources = arch_types + "\n" + backend_types
    forbidden_geometry = re.compile(r"\b(?:M64K_)?(?:VLEN|VECTOR_LENGTH|TILE_ROWS|TILE_COLUMNS|MATRIX_ROWS|MATRIX_COLUMNS)\b")
    match = forbidden_geometry.search(base_contract_sources)
    if match is not None:
        raise AlignmentError(f"base interface freezes deferred vector/matrix geometry through {match.group(0)!r}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=REPOSITORY_ROOT)
    arguments = parser.parse_args(argv)

    try:
        validate_alignment(arguments.repository_root.resolve())
    except (AlignmentError, KeyError, TypeError) as error:
        print(f"first-product alignment error: {error}", file=sys.stderr)
        return 1

    print("M64K first-product interfaces aligned: native64, 4C2T identities, PA48 carrier, ROB-192 identity capacity, 64-bit allocation lifetime, four retirement lanes; implementation remains unclaimed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
