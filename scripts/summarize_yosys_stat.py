#!/usr/bin/env python3
"""Create a stable generic-synthesis summary from Yosys statistics."""

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


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as input_file:
        for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stat", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--tool-lock", required=True, type=Path)
    parser.add_argument("--flow", required=True, type=Path)
    parser.add_argument("--netlist", required=True, type=Path)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--top", required=True)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    try:
        statistics = json.loads(arguments.stat.read_text(encoding="utf-8"))
        tool_lock = json.loads(arguments.tool_lock.read_text(encoding="utf-8"))
        source_names = validated_source_names(arguments.manifest)
        modules = statistics["modules"]
        module = modules.get(arguments.top, modules.get(f"\\{arguments.top}"))
        if module is None:
            raise KeyError(f"top module {arguments.top!r} is absent from Yosys statistics")
    except (OSError, KeyError, ManifestValidationError, json.JSONDecodeError) as error:
        print(f"QoR summary error: {error}", file=sys.stderr)
        return 1

    summary = {
        "schema_version": 1,
        "target": arguments.target,
        "stage": "generic-synthesis",
        "top": arguments.top,
        "tool_image": tool_lock["image"],
        "flow_sha256": hash_file(arguments.flow),
        "creator": statistics.get("creator", "unknown"),
        "manifest_sha256": hash_file(arguments.manifest),
        "source_sha256": {source: hash_file(REPOSITORY_ROOT / source) for source in source_names},
        "output_sha256": {
            "netlist": hash_file(arguments.netlist),
            "statistics": hash_file(arguments.stat),
            "synthesis_log": hash_file(arguments.log),
        },
        "metrics": {
            "wires": module.get("num_wires", 0),
            "wire_bits": module.get("num_wire_bits", 0),
            "ports": module.get("num_ports", 0),
            "port_bits": module.get("num_port_bits", 0),
            "memories": module.get("num_memories", 0),
            "memory_bits": module.get("num_memory_bits", 0),
            "processes": module.get("num_processes", 0),
            "cells": module.get("num_cells", 0),
            "cell_types": module.get("num_cells_by_type", {}),
        },
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"PASS: {arguments.target} generic synthesis contains {summary['metrics']['cells']} cells")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
