#!/usr/bin/env python3
"""Create a reproducible result record for one successful Yosys SAT equivalence proof."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

if __package__:
    from .check_asic_manifest import ManifestValidationError, validated_source_names
else:
    from check_asic_manifest import ManifestValidationError, validated_source_names


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SUCCESS_MARKER = "SAT proof finished - no model found: SUCCESS!"


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as input_file:
        for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_hashes(manifest: Path) -> dict[str, str]:
    return {source: hash_file(REPOSITORY_ROOT / source) for source in validated_source_names(manifest)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--reference-manifest", required=True, type=Path)
    parser.add_argument("--candidate-manifest", required=True, type=Path)
    parser.add_argument("--candidate-netlist", required=True, type=Path)
    parser.add_argument("--miter", required=True, type=Path)
    parser.add_argument("--tool-lock", required=True, type=Path)
    parser.add_argument("--flow", required=True, type=Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    try:
        proof_log = arguments.log.read_text(encoding="utf-8", errors="replace")
        if proof_log.count(SUCCESS_MARKER) != 1:
            raise ValueError("proof log must contain exactly one Yosys SAT success marker")

        tool_lock = json.loads(arguments.tool_lock.read_text(encoding="utf-8"))
        reference_sources = source_hashes(arguments.reference_manifest)
        candidate_sources = source_hashes(arguments.candidate_manifest)
        tool_image = tool_lock["image"]
    except (OSError, KeyError, ManifestValidationError, ValueError, json.JSONDecodeError) as error:
        print(f"Equivalence summary error: {error}", file=sys.stderr)
        return 1

    summary = {
        "schema_version": 1,
        "target": arguments.target,
        "stage": "formal-combinational-equivalence",
        "result": "proven",
        "engine": "Yosys internal MiniSAT",
        "tool_image": tool_image,
        "flow_sha256": hash_file(arguments.flow),
        "reference_manifest_sha256": hash_file(arguments.reference_manifest),
        "candidate_manifest_sha256": hash_file(arguments.candidate_manifest),
        "reference_source_sha256": reference_sources,
        "candidate_source_sha256": candidate_sources,
        "candidate_netlist_sha256": hash_file(arguments.candidate_netlist),
        "miter_sha256": hash_file(arguments.miter),
        "proof_log_sha256": hash_file(arguments.log),
    }

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"PASS: {arguments.target} formal equivalence proven and hashed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
