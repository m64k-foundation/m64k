#!/usr/bin/env python3
"""Verify structural closure of the declarative MC68060 cut-line inventory."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "isa" / "native" / "mc68060-semantic-cut-line.json"

ALLOWED_CLASSIFICATIONS = {"direct", "microcoded", "one-to-one-alias", "modern-replacement", "rejected", "unclassified"}

EXPECTED_REJECTED_TABLE_ROWS = {
    "ANDI_TO_CCR", "ANDI_TO_SR", "EORI_TO_CCR", "EORI_TO_SR", "MOVE_FROM_CCR", "MOVE_TO_CCR",
    "MOVE_FROM_SR", "MOVE_TO_SR", "MOVE_USP", "ORI_TO_CCR", "ORI_TO_SR", "RTR",
}

EXPECTED_TABLE_1_3 = {
    "ABCD", "ADD", "ADDA", "ADDI", "ADDQ", "ADDX", "AND", "ANDI", "ANDI_TO_CCR", "ANDI_TO_SR", "ASL_ASR",
    "Bcc", "BCHG", "BCLR", "BFCHG", "BFCLR", "BFEXTS", "BFEXTU", "BFFFO", "BFINS", "BFSET", "BFTST",
    "BKPT", "BRA", "BSET", "BSR", "BTST",
    "CAS", "CAS2", "CHK", "CHK2", "CINV", "CLR", "CMP", "CMPA", "CMPI", "CMPM", "CMP2", "CPUSH",
    "DBcc", "DIVS_DIVSL", "DIVU_DIVUL",
    "EOR", "EORI", "EORI_TO_CCR", "EORI_TO_SR", "EXG", "EXT_EXTB",
    "FABS", "FADD", "FBcc", "FCMP", "FDBcc", "FDIV", "FINT", "FINTRZ", "FMOVE_DATA", "FMOVE_CONTROL",
    "FMOVEM_DATA", "FMOVEM_CONTROL", "FMUL", "FNEG", "FNOP", "FRESTORE", "FSAVE", "FScc", "FSGLDIV",
    "FSGLMUL", "FSQRT", "FSUB", "FTRAPcc", "FTST",
    "ILLEGAL", "JMP", "JSR", "LEA", "LINK", "LPSTOP", "LSL_LSR",
    "MOVE", "MOVEA", "MOVE_FROM_CCR", "MOVE_TO_CCR", "MOVE_FROM_SR", "MOVE_TO_SR", "MOVE_USP", "MOVE16",
    "MOVEC", "MOVEM", "MOVEP", "MOVEQ", "MOVES", "MULS", "MULU",
    "NBCD", "NEG", "NEGX", "NOP", "NOT", "OR", "ORI", "ORI_TO_CCR", "ORI_TO_SR",
    "PACK", "PEA", "PFLUSH", "PLPA", "RESET", "ROL_ROR", "ROXL_ROXR", "RTD", "RTE", "RTR", "RTS",
    "SBCD", "Scc", "STOP", "SUB", "SUBA", "SUBI", "SUBQ", "SUBX", "SWAP",
    "TAS", "TRAP", "TRAPcc", "TRAPV", "TST", "UNLK", "UNPK",
}

EXPECTED_APPENDIX_C_INTEGER = {
    "DIVU_L_64_BY_32",
    "DIVS_L_64_BY_32",
    "MULU_L_32_BY_32_TO_64",
    "MULS_L_32_BY_32_TO_64",
    "MOVEP_REGISTER_TO_MEMORY_W_OR_L",
    "MOVEP_MEMORY_TO_REGISTER_W_OR_L",
    "CHK2_B_W_OR_L",
    "CMP2_B_W_OR_L",
    "CAS2_W_OR_L",
    "CAS_MISALIGNED_W_OR_L",
}

EXPECTED_APPENDIX_C_FP = {
    "FACOS", "FASIN", "FATAN", "FATANH", "FCOS", "FCOSH", "FETOX", "FETOXM1", "FGETEXP", "FGETMAN",
    "FLOG10", "FLOG2", "FLOGN", "FLOGNP1", "FMOVECR", "FSIN", "FSINCOS", "FSINH", "FTAN", "FTANH",
    "FTENTOX", "FTWOTOX", "FMOD", "FREM", "FSCALE",
}

EXPECTED_APPENDIX_C_FP_CONDITIONALS = {"C3_FTRAPcc", "C3_FDBcc", "C3_FScc"}
EXPECTED_APPENDIX_C_FP_EFFECTIVE_ADDRESS_FORMS = {
    "C3_FMOVEM_X_DYNAMIC_REGISTER_LIST",
    "C3_FMOVEM_L_IMMEDIATE_CONTROL_LIST",
    "C3_FOP_X_IMMEDIATE",
    "C3_FOP_P_IMMEDIATE",
}
EXPECTED_APPENDIX_C_OPERAND_TYPE_MATRIX = [
    ("normalized", ["hardware-implemented", "hardware-implemented", "hardware-implemented", "software-package-handled", "hardware-implemented", "hardware-implemented", "hardware-implemented"]),
    ("zero", ["hardware-implemented", "hardware-implemented", "hardware-implemented", "software-package-handled", "hardware-implemented", "hardware-implemented", "hardware-implemented"]),
    ("infinity", ["hardware-implemented", "hardware-implemented", "hardware-implemented", "software-package-handled", "not-applicable", "not-applicable", "not-applicable"]),
    ("nan", ["hardware-implemented", "hardware-implemented", "hardware-implemented", "software-package-handled", "not-applicable", "not-applicable", "not-applicable"]),
    ("denormalized", ["software-package-handled", "software-package-handled", "software-package-handled", "software-package-handled", "not-applicable", "not-applicable", "not-applicable"]),
    ("unnormalized", ["not-applicable", "not-applicable", "software-package-handled", "software-package-handled", "not-applicable", "not-applicable", "not-applicable"]),
]


class InventoryError(ValueError):
    """The cut-line inventory is incomplete or structurally inconsistent."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise InventoryError(message)


def require_unique_ids(entries: list[dict[str, object]], section: str) -> set[str]:
    identifiers = [str(entry["baseline_id"]) for entry in entries]
    duplicates = sorted(identifier for identifier in set(identifiers) if identifiers.count(identifier) > 1)
    require(not duplicates, f"{section} contains duplicate baseline IDs: {duplicates}")
    return set(identifiers)


def require_complete_rows(entries: list[dict[str, object]], section: str) -> None:
    for entry in entries:
        identifier = entry.get("baseline_id", "<missing>")
        require(entry.get("classification") in ALLOWED_CLASSIFICATIONS, f"{section}:{identifier} has an invalid proposed classification")
        require(entry.get("review_status") == "draft", f"{section}:{identifier} must remain draft until semantic review")


def main() -> None:
    inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))

    require(inventory["status"] == "draft", "inventory must remain draft until every semantic row is approved")
    require(inventory["classification_status"] == "proposed-until-row-review", "classifications must remain explicitly provisional")

    sources = inventory["sources"]
    require(sources["table_1_3"]["section"] == "1.9 Instruction Set Overview, Table 1-3 Instruction Set Summary", "Table 1-3 citation changed")
    require(sources["table_1_3"]["printed_pages"] == "1-16 through 1-20", "Table 1-3 page range changed")
    require(sources["appendix_c_integer"]["printed_pages"] == "C-4 through C-5", "Appendix C integer page range changed")
    require(sources["appendix_c_fp"]["printed_pages"] == "C-13", "Appendix C floating-point page range changed")

    table_entries = inventory["table_1_3_entries"]
    appendix_integer = inventory["appendix_c_integer_variants"]
    appendix_fp = inventory["appendix_c_fp_families"]
    appendix_fp_conditionals = inventory["appendix_c_fp_conditionals"]
    appendix_fp_effective_address_forms = inventory["appendix_c_fp_effective_address_forms"]
    rejected_fp_formats = inventory["rejected_fp_formats"]

    table_ids = require_unique_ids(table_entries, "table_1_3_entries")
    appendix_integer_ids = require_unique_ids(appendix_integer, "appendix_c_integer_variants")
    appendix_fp_ids = require_unique_ids(appendix_fp, "appendix_c_fp_families")
    appendix_fp_conditional_ids = require_unique_ids(appendix_fp_conditionals, "appendix_c_fp_conditionals")
    appendix_fp_effective_address_ids = require_unique_ids(appendix_fp_effective_address_forms, "appendix_c_fp_effective_address_forms")
    require_unique_ids(rejected_fp_formats, "rejected_fp_formats")

    require_complete_rows(table_entries, "table_1_3_entries")
    require_complete_rows(appendix_integer, "appendix_c_integer_variants")
    require_complete_rows(appendix_fp, "appendix_c_fp_families")
    require_complete_rows(rejected_fp_formats, "rejected_fp_formats")

    require(table_ids == EXPECTED_TABLE_1_3, "Table 1-3 inventory differs from the independently reviewed identifier set")
    require(appendix_integer_ids == EXPECTED_APPENDIX_C_INTEGER, "Appendix C integer inventory differs from the independently reviewed identifier set")
    require(appendix_fp_ids == EXPECTED_APPENDIX_C_FP, "Appendix C floating-point inventory differs from the independently reviewed identifier set")
    require(appendix_fp_conditional_ids == EXPECTED_APPENDIX_C_FP_CONDITIONALS, "Appendix C floating-point conditional inventory differs from Table C-3")
    require(appendix_fp_effective_address_ids == EXPECTED_APPENDIX_C_FP_EFFECTIVE_ADDRESS_FORMS, "Appendix C floating-point effective-address-form inventory differs from Table C-3")
    require({entry["baseline_id"] for entry in table_entries if entry["classification"] == "rejected"} == EXPECTED_REJECTED_TABLE_ROWS, "proposed rejected Table 1-3 rows changed without review")
    require({entry["baseline_id"] for entry in appendix_integer if entry["classification"] == "rejected"} == {"CAS_MISALIGNED_W_OR_L"}, "proposed rejected Appendix C integer rows changed without review")
    require(not [entry for entry in appendix_fp if entry["classification"] == "rejected"], "computational Appendix C FP families require a native analogue")

    parented_entries = appendix_integer + appendix_fp_conditionals + appendix_fp_effective_address_forms
    missing_parents = sorted(
        str(entry["parent_table_1_3_id"])
        for entry in parented_entries
        if entry["parent_table_1_3_id"] not in table_ids
    )
    require(not missing_parents, f"Appendix C variants refer to missing Table 1-3 parents: {missing_parents}")

    operand_type_matrix = inventory["appendix_c_operand_type_matrix"]
    require(operand_type_matrix["columns"] == ["sgl", "dbl", "ext", "dec", "byte", "word", "long"], "Appendix C Table C-4 columns differ from the reviewed source")
    actual_operand_type_matrix = [(row["value_class"], row["statuses"]) for row in operand_type_matrix["rows"]]
    require(actual_operand_type_matrix == EXPECTED_APPENDIX_C_OPERAND_TYPE_MATRIX, "Appendix C Table C-4 cells differ from the reviewed source")
    require(operand_type_matrix["review_status"] == "draft", "Appendix C Table C-4 must remain draft until semantic disposition review")

    categories = {str(entry["category"]) for entry in table_entries}
    require(any(category.startswith("integer") for category in categories), "integer instruction categories are missing")
    require(any(category.startswith("floating") for category in categories), "floating-point instruction categories are missing")
    require(any(category.endswith("system") for category in categories), "system instruction categories are missing")

    print(
        "MC68060 instruction-name inventory is structurally consistent but semantically draft: "
        f"{len(table_ids)} Table 1-3 rows, "
        f"{len(appendix_integer_ids)} Appendix C integer variants, "
        f"{len(appendix_fp_ids)} Appendix C floating-point operation families, "
        f"{len(appendix_fp_conditional_ids) + len(appendix_fp_effective_address_ids)} additional Table C-3 forms, "
        "and all 42 Table C-4 cells."
    )


if __name__ == "__main__":
    main()
