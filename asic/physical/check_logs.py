#!/usr/bin/env python3
"""Fail an M64K physical exploration when any tool log reports a warning or error."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
from typing import Any


DIAGNOSTIC = re.compile(r"^\s*(?:\[(?:warning|error|fatal)\b|(?:warning|error|fatal)\s*:)", re.IGNORECASE)
REQUIRED_EMPTY_REPORT_FAMILIES = ("5_route_drc.rpt", "drt_antennas.log", "6_constraint_integrity.rpt")
FINAL_REPORT_METRICS = {
    "max slew violation count": "finish__timing__drv__max_slew",
    "max fanout violation count": "finish__timing__drv__max_fanout",
    "max cap violation count": "finish__timing__drv__max_cap",
    "setup violation count": "finish__timing__drv__setup_violation_count",
    "hold violation count": "finish__timing__drv__hold_violation_count",
}
REQUIRED_ZERO_METRICS = (
    "finish__timing__setup__tns",
    "finish__timing__hold__tns",
    "finish__timing__drv__max_slew",
    "finish__timing__drv__max_cap",
    "finish__timing__drv__max_fanout",
    "finish__timing__drv__setup_violation_count",
    "finish__timing__drv__hold_violation_count",
    "finish__flow__warnings__count",
    "finish__flow__errors__count",
)
REQUIRED_NONNEGATIVE_METRICS = ("finish__timing__setup__ws", "finish__timing__hold__ws")
REQUIRED_POSITIVE_METRICS = ("finish__timing__fmax",)


def reported_diagnostics(log_root: Path) -> list[str]:
    diagnostics: list[str] = []

    for log_path in sorted(log_root.rglob("*.log")):
        relative_path = log_path.relative_to(log_root)
        with log_path.open(encoding="utf-8", errors="strict") as log_file:
            for line_number, line in enumerate(log_file, start=1):
                if DIAGNOSTIC.search(line):
                    diagnostics.append(f"{relative_path}:{line_number}: {line.rstrip()}")

    return diagnostics


def report_failures(report_root: Path) -> list[str]:
    failures: list[str] = []

    for report_name in REQUIRED_EMPTY_REPORT_FAMILIES:
        canonical_report = report_root / report_name
        if not canonical_report.is_file():
            failures.append(f"missing required physical report: {report_name}")
            continue

        report_paths = sorted(path for path in report_root.glob(f"{report_name}*") if path.is_file())
        for report_path in report_paths:
            if report_path.read_text(encoding="utf-8", errors="strict").strip():
                failures.append(f"physical report is not empty: {report_path.name}")

    return failures


def _coalesce_identical_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    required_metrics = set(REQUIRED_ZERO_METRICS + REQUIRED_NONNEGATIVE_METRICS + REQUIRED_POSITIVE_METRICS)

    for key, value in pairs:
        if key in required_metrics and key in result and result[key] != value:
            raise ValueError(f"conflicting duplicate JSON key: {key}")
        result[key] = value

    return result


def _finite_number(metrics: dict[str, Any], key: str, failures: list[str]) -> float | None:
    if key not in metrics:
        failures.append(f"missing required final metric: {key}")
        return None

    value = metrics[key]
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        failures.append(f"invalid final metric {key}: {value!r}")
        return None

    return float(value)


def final_timing_failures(log_root: Path, report_root: Path) -> list[str]:
    failures: list[str] = []
    metrics_path = log_root / "6_report.json"
    final_report_path = report_root / "6_finish.rpt"

    if not metrics_path.is_file():
        failures.append("missing required final metrics: 6_report.json")
        metrics: dict[str, Any] = {}
    else:
        try:
            metrics = json.loads(metrics_path.read_text(encoding="utf-8", errors="strict"), object_pairs_hook=_coalesce_identical_json_keys)
        except (json.JSONDecodeError, ValueError) as error:
            failures.append(f"invalid final metrics 6_report.json: {error}")
            metrics = {}

    metric_values: dict[str, float] = {}
    for key in REQUIRED_ZERO_METRICS + REQUIRED_NONNEGATIVE_METRICS + REQUIRED_POSITIVE_METRICS:
        value = _finite_number(metrics, key, failures)
        if value is not None:
            metric_values[key] = value

    for key in REQUIRED_ZERO_METRICS:
        if key in metric_values and metric_values[key] != 0.0:
            failures.append(f"nonzero final metric {key}: {metric_values[key]:g}")

    for key in REQUIRED_NONNEGATIVE_METRICS:
        if key in metric_values and metric_values[key] < 0.0:
            failures.append(f"negative final timing slack {key}: {metric_values[key]:g}")

    for key in REQUIRED_POSITIVE_METRICS:
        if key in metric_values and metric_values[key] <= 0.0:
            failures.append(f"nonpositive final metric {key}: {metric_values[key]:g}")

    if not final_report_path.is_file():
        failures.append("missing required final timing report: 6_finish.rpt")
        return failures

    final_report = final_report_path.read_text(encoding="utf-8", errors="strict")
    worst_slack_matches = re.findall(r"^worst slack max\s+([-+0-9.eE]+)\s*$", final_report, re.MULTILINE)
    if len(worst_slack_matches) != 1:
        failures.append(f"expected exactly one final worst-slack value, found {len(worst_slack_matches)}")
    else:
        try:
            worst_slack = float(worst_slack_matches[0])
        except ValueError:
            failures.append(f"invalid final worst-slack value: {worst_slack_matches[0]!r}")
        else:
            if not math.isfinite(worst_slack) or worst_slack < 0.0:
                failures.append(f"negative or non-finite final worst slack: {worst_slack_matches[0]}")

    for report_label, metric_key in FINAL_REPORT_METRICS.items():
        matches = re.findall(rf"^{re.escape(report_label)}\s+([0-9]+)\s*$", final_report, re.MULTILINE)
        if len(matches) != 1:
            failures.append(f"expected exactly one '{report_label}' value, found {len(matches)}")
            continue

        report_value = int(matches[0])
        if report_value != 0:
            failures.append(f"nonzero final report value {report_label}: {report_value}")
        if metric_key in metric_values and report_value != metric_values[metric_key]:
            failures.append(f"final report/metric mismatch for {report_label}: report={report_value} metric={metric_values[metric_key]:g}")

    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log_root", type=Path)
    parser.add_argument("--report-root", required=True, type=Path)
    arguments = parser.parse_args()

    if not arguments.log_root.is_dir():
        parser.error(f"log directory does not exist: {arguments.log_root}")
    if not arguments.report_root.is_dir():
        parser.error(f"report directory does not exist: {arguments.report_root}")

    diagnostics = reported_diagnostics(arguments.log_root)
    failures = report_failures(arguments.report_root)
    failures.extend(final_timing_failures(arguments.log_root, arguments.report_root))
    if diagnostics or failures:
        print("physical-flow diagnostic audit failed:")
        for diagnostic in diagnostics:
            print(f"  {diagnostic}")
        for failure in failures:
            print(f"  {failure}")
        return 1

    print(f"physical-flow diagnostic audit passed: {arguments.log_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
