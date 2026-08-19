#!/usr/bin/env python3
"""Require every advertised M00 decode format to have an explicit audit state."""

from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path
import sys


STATUSES = {"verified", "partial", "unverified"}
FLAG_NAMES = {"X", "N", "Z", "V", "C"}
CONTRACT_LIST_FIELDS = {
    "manual_sections", "sizes", "effective_addresses", "memory_sequence",
    "exceptions", "coverage_domains", "model_limits",
}


def load_json(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: top level must be an object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("decoder", type=Path)
    parser.add_argument("audit", type=Path)
    parser.add_argument("--contracts", type=Path)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    try:
        decoder = load_json(args.decoder)
        audit = load_json(args.audit)
        contracts_path = args.contracts or args.audit.with_name(
            args.audit.stem.removesuffix("_audit") + "_contracts.json"
        )
        contracts_document = load_json(contracts_path)
        if decoder.get("schema") != 1 or decoder.get("profile") != "M00":
            raise ValueError("decoder must use schema 1 and profile M00")
        if audit.get("schema") != 1 or audit.get("profile") != "M00":
            raise ValueError("audit must use schema 1 and profile M00")
        if (contracts_document.get("schema") != 1 or
                contracts_document.get("profile") != "M00"):
            raise ValueError("manual contracts must use schema 1 and profile M00")

        instructions = decoder.get("instructions")
        formats = audit.get("formats")
        contracts = contracts_document.get("formats")
        if (not isinstance(instructions, list) or not isinstance(formats, dict) or
                not isinstance(contracts, dict)):
            raise ValueError("invalid instructions/formats containers")

        advertised = {str(entry["format"]) for entry in instructions}
        recorded = set(formats)
        if advertised != recorded:
            missing = sorted(advertised - recorded)
            stale = sorted(recorded - advertised)
            raise ValueError(f"audit inventory mismatch: missing={missing}, stale={stale}")
        if audit.get("decoder_patterns") != len(instructions):
            raise ValueError(
                f"decoder_patterns is {audit.get('decoder_patterns')}, expected {len(instructions)}"
            )

        counts: collections.Counter[str] = collections.Counter()
        for name in sorted(formats):
            entry = formats[name]
            if not isinstance(entry, dict):
                raise ValueError(f"{name}: audit entry must be an object")
            status = entry.get("status")
            if status not in STATUSES:
                raise ValueError(f"{name}: invalid status {status!r}")
            if not isinstance(entry.get("scope"), str) or not entry["scope"].strip():
                raise ValueError(f"{name}: non-empty scope is required")
            references = entry.get("references")
            evidence = entry.get("evidence")
            if not isinstance(references, list) or not isinstance(evidence, list):
                raise ValueError(f"{name}: references/evidence must be arrays")
            if status != "unverified" and (not references or not evidence):
                raise ValueError(f"{name}: {status} entries require references and evidence")
            counts[str(status)] += 1

        verified = {name for name, entry in formats.items()
                    if entry.get("status") == "verified"}
        if set(contracts) != verified:
            missing = sorted(verified - set(contracts))
            stale = sorted(set(contracts) - verified)
            raise ValueError(
                f"manual contract inventory mismatch: missing={missing}, stale={stale}"
            )

        for name in sorted(contracts):
            contract = contracts[name]
            if not isinstance(contract, dict):
                raise ValueError(f"{name}: manual contract must be an object")
            for field in CONTRACT_LIST_FIELDS:
                value = contract.get(field)
                if (not isinstance(value, list) or not value or
                        any(not isinstance(item, str) or not item.strip()
                            for item in value)):
                    raise ValueError(
                        f"{name}: contract {field} must be a non-empty string array"
                    )
            if not isinstance(contract.get("operation"), str) or not contract["operation"].strip():
                raise ValueError(f"{name}: contract operation is required")
            if not isinstance(contract.get("encoding"), str) or not contract["encoding"].strip():
                raise ValueError(f"{name}: contract encoding is required")
            legal_words = contract.get("legal_opcode_words")
            if not isinstance(legal_words, int) or isinstance(legal_words, bool) or legal_words <= 0:
                raise ValueError(f"{name}: positive legal_opcode_words is required")
            flags = contract.get("flags")
            if not isinstance(flags, dict) or set(flags) != FLAG_NAMES:
                raise ValueError(f"{name}: contract flags must define exactly X/N/Z/V/C")
            if any(not isinstance(value, str) or not value.strip()
                   for value in flags.values()):
                raise ValueError(f"{name}: every flag rule must be non-empty")
            audit_references = set(formats[name]["references"])
            if not set(contract["manual_sections"]).issubset(audit_references):
                raise ValueError(
                    f"{name}: contract manual sections must also appear in audit references"
                )
            required_domains = {"encoding", "operation", "flags", "exceptions"}
            if not required_domains.issubset(set(contract["coverage_domains"])):
                raise ValueError(
                    f"{name}: coverage_domains must include {sorted(required_domains)}"
                )

        print(
            f"M00 audit inventory: {len(instructions)} patterns, {len(formats)} formats; "
            f"verified={counts['verified']} partial={counts['partial']} "
            f"unverified={counts['unverified']}"
        )
        if args.require_complete and (counts["partial"] or counts["unverified"]):
            return 1
        return 0
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"audit database error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
