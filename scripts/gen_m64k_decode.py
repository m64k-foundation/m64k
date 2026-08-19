#!/usr/bin/env python3
"""Validate an M64K ISA subset and generate its synthesizable lookup table."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any


FORMAT_ORDER = (
    "ADD_EA_DN", "ADDSUB_ADDRESS", "ADDSUB_IMMEDIATE", "ADDX_SUBX_REGISTER", "ADDX_SUBX_MEMORY", "ABCD_SBCD", "ADDQ_SUBQ", "BINARY_DN_EA", "BINARY_EA_DN", "BIT_DYNAMIC", "BIT_IMMEDIATE", "BRANCH", "CLR", "CMPM",
    "CHK", "CMP_IMMEDIATE", "CMPA", "DBCC", "DIV", "EXG", "EXT", "ILLEGAL", "JMP", "JSR", "LEA", "LINK",
    "LOGICAL_IMMEDIATE", "LOGICAL_IMMEDIATE_SR", "MOVE", "MOVE_FROM_SR", "MOVE_TO_CCR", "MOVE_TO_SR", "MOVE_USP", "MOVEM", "MUL", "NEG", "NOP", "NOT",
    "PEA", "RESET", "SHIFT_MEMORY", "SHIFT_REGISTER", "SWAP", "UNLINK", "NEGX", "NBCD",
    "RTE", "RTR", "RTS", "SCC", "STOP", "TAS", "TEST", "TRAP", "TRAPV", "MOVEQ",
)
FORMATS = set(FORMAT_ORDER)
MAX_LEAF_PATTERNS = 4


def load_database(path: Path) -> list[dict[str, object]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schema") != 1 or document.get("profile") != "M00":
        raise ValueError("expected schema 1 and profile M00")
    entries = document.get("instructions")
    if not isinstance(entries, list) or not entries:
        raise ValueError("instructions must be a non-empty list")

    seen_ids: set[int] = set()
    seen_names: set[str] = set()
    result: list[dict[str, object]] = []
    for raw in entries:
        entry = dict(raw)
        ident = int(entry["id"])
        name = str(entry["name"])
        mask = int(str(entry["mask"]), 16)
        value = int(str(entry["value"]), 16)
        form = str(entry["format"])
        if not 1 <= ident <= 255 or ident in seen_ids:
            raise ValueError(f"invalid or duplicate instruction id {ident}")
        if not name.isidentifier() or name.upper() != name or name in seen_names:
            raise ValueError(f"invalid or duplicate instruction name {name!r}")
        if not 0 <= mask <= 0xffff or value & ~mask:
            raise ValueError(f"{name}: value sets bits outside mask")
        if form not in FORMATS:
            raise ValueError(f"{name}: unsupported format {form}")
        seen_ids.add(ident)
        seen_names.add(name)
        entry.update(id=ident, name=name, mask=mask, value=value, format=form)
        result.append(entry)

    for index, lhs in enumerate(result):
        for rhs in result[index + 1:]:
            lhs_mask = int(lhs["mask"])
            rhs_mask = int(rhs["mask"])
            common = lhs_mask & rhs_mask
            if (int(lhs["value"]) & common) == (int(rhs["value"]) & common):
                # The 68k encoding contains intentional sub-decodes (for
                # example ILLEGAL lives inside the broad TST encoding space).
                # Accept only a strict mask containment; specificity sorting
                # below then gives the sub-decode deterministic priority.
                masks_are_nested = ((lhs_mask | rhs_mask) == lhs_mask) or \
                                   ((lhs_mask | rhs_mask) == rhs_mask)
                if (lhs_mask == rhs_mask) or not masks_are_nested:
                    raise ValueError(
                        f"ambiguous opcode patterns: {lhs['name']} and {rhs['name']}"
                    )

    return sorted(result, key=lambda item: (-int(item["mask"]).bit_count(), int(item["id"])))


def opcode_matches(item: dict[str, object], opcode: int) -> bool:
    mask = int(item["mask"])
    return (opcode & mask) == int(item["value"])


def build_decode_tree(
    entries: list[dict[str, object]], bits: tuple[int, ...]
) -> tuple[Any, ...]:
    """Build a balanced bit decision tree while retaining leaf priority.

    Patterns with a don't-care at the selected bit are present in both child
    nodes.  Leaves therefore keep the specificity-sorted entry order, which
    preserves intentional nested decodes such as ILLEGAL inside TST.
    """
    if len(entries) <= MAX_LEAF_PATTERNS or not bits:
        return ("leaf", entries)

    candidates: list[tuple[int, int, int, list[dict[str, object]],
                           list[dict[str, object]]]] = []
    for bit in bits:
        bit_mask = 1 << bit
        child_zero = [entry for entry in entries
                      if not (int(entry["mask"]) & bit_mask) or
                      not (int(entry["value"]) & bit_mask)]
        child_one = [entry for entry in entries
                     if not (int(entry["mask"]) & bit_mask) or
                     (int(entry["value"]) & bit_mask)]
        if len(child_zero) == len(entries) and len(child_one) == len(entries):
            continue
        candidates.append((max(len(child_zero), len(child_one)),
                           len(child_zero) + len(child_one), -bit,
                           child_zero, child_one))
    if not candidates:
        return ("leaf", entries)

    _, _, negative_bit, child_zero, child_one = min(
        candidates, key=lambda candidate: candidate[:3]
    )
    selected_bit = -negative_bit
    remaining = tuple(bit for bit in bits if bit != selected_bit)
    return ("bit", selected_bit,
            build_decode_tree(child_zero, remaining),
            build_decode_tree(child_one, remaining))


def lookup_tree(tree: tuple[Any, ...], opcode: int) -> dict[str, object] | None:
    if tree[0] == "leaf":
        for entry in tree[1]:
            if opcode_matches(entry, opcode):
                return entry
        return None
    selected = tree[3] if opcode & (1 << int(tree[1])) else tree[2]
    return lookup_tree(selected, opcode)


def render_leaf(entries: list[dict[str, object]], indent: str) -> list[str]:
    lines: list[str] = []
    for index, item in enumerate(entries):
        prefix = "if" if index == 0 else "else if"
        lines.extend([
            f"{indent}{prefix} ((opcode & 16'h{int(item['mask']):04x}) == "
            f"16'h{int(item['value']):04x}) begin",
            f"{indent}    result.matched = 1'b1;",
            f"{indent}    result.instruction_id = M64K_INSN_{item['name']};",
            f"{indent}    result.format = M64K_DECODE_{item['format']};",
            f"{indent}end",
        ])
    return lines


def render_decode_tree(tree: tuple[Any, ...], indent: str) -> list[str]:
    if tree[0] == "leaf":
        return render_leaf(tree[1], indent)
    bit = int(tree[1])
    lines = [f"{indent}if (opcode[{bit}]) begin"]
    lines.extend(render_decode_tree(tree[3], indent + "    "))
    lines.append(f"{indent}end else begin")
    lines.extend(render_decode_tree(tree[2], indent + "    "))
    lines.append(f"{indent}end")
    return lines


def render(entries: list[dict[str, object]], source: Path) -> str:
    enum_ids = ["        M64K_INSN_UNKNOWN = 8'd0"]
    enum_ids.extend(
        f"        M64K_INSN_{item['name']} = 8'd{item['id']}" for item in entries
    )
    used_formats = {str(item["format"]) for item in entries}
    formats = [name for name in FORMAT_ORDER if name in used_formats]
    enum_formats = ["        M64K_DECODE_NONE = 6'd0"]
    enum_formats.extend(
        f"        M64K_DECODE_{name} = 6'd{index}"
        for index, name in enumerate(formats, start=1)
    )

    major_groups: dict[int, list[dict[str, object]]] = {}
    decode_trees: dict[int, tuple[Any, ...]] = {}
    for item in entries:
        if (int(item["mask"]) & 0xf000) != 0xf000:
            raise ValueError(
                f"{item['name']}: hierarchical M00 decode requires a fixed major nibble"
            )
        major_groups.setdefault(int(item["value"]) >> 12, []).append(item)
    for major, group in major_groups.items():
        decode_trees[major] = build_decode_tree(group, tuple(range(11, -1, -1)))

    # Exhaustive generator-side equivalence prevents a tree optimization from
    # changing overlap priority or the set of matched 16-bit words.
    for opcode in range(0x10000):
        reference = next((item for item in entries if opcode_matches(item, opcode)), None)
        tree_match = lookup_tree(decode_trees[opcode >> 12], opcode) \
            if (opcode >> 12) in decode_trees else None
        reference_id = int(reference["id"]) if reference is not None else 0
        tree_id = int(tree_match["id"]) if tree_match is not None else 0
        if reference_id != tree_id:
            raise ValueError(
                f"hierarchical decode mismatch at 0x{opcode:04x}: "
                f"linear={reference_id} tree={tree_id}"
            )

    lookup_lines = ["            case (opcode[15:12])"]
    for major in sorted(decode_trees):
        lookup_lines.append(f"                4'h{major:x}: begin")
        lookup_lines.extend(render_decode_tree(decode_trees[major], "                    "))
        lookup_lines.append("                end")
    lookup_lines.extend(["                default: begin end", "            endcase"])

    return f"""// Generated by scripts/gen_m64k_decode.py from isa/{source.name}.
// Do not edit this file directly.
package m64k_m00_decode_table_pkg;
    typedef enum logic [7:0] {{
{',\n'.join(enum_ids)}
    }} m64k_instruction_id_t;

    typedef enum logic [5:0] {{
{',\n'.join(enum_formats)}
    }} m64k_decode_format_t;

    typedef struct packed {{
        logic matched;
        m64k_instruction_id_t instruction_id;
        m64k_decode_format_t format;
    }} m64k_decode_match_t;

    function automatic m64k_decode_match_t m64k_lookup_m00_opcode(
        input logic [15:0] opcode
    );
        m64k_decode_match_t result;
        begin
            result = '0;
{chr(10).join(lookup_lines)}
            return result;
        end
    endfunction
endpackage
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        generated = render(load_database(args.database), args.database)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"decode database error: {error}", file=sys.stderr)
        return 2

    if args.check:
        current = args.output.read_text(encoding="utf-8") if args.output.exists() else ""
        if current != generated:
            print(f"generated decode table is stale: {args.output}", file=sys.stderr)
            return 1
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(generated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
