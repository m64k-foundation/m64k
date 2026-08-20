#!/usr/bin/env python3
"""Unit tests for the fatal physical-flow diagnostic audit."""

from __future__ import annotations

from pathlib import Path
import json
import tempfile
import unittest

from asic.physical.check_logs import final_timing_failures, report_failures, reported_diagnostics


VALID_FINAL_REPORT = """worst slack max 1.25
max slew violation count 0
max fanout violation count 0
max cap violation count 0
setup violation count 0
hold violation count 0
"""

VALID_FINAL_METRICS = {
    "finish__timing__setup__tns": 0,
    "finish__timing__hold__tns": 0,
    "finish__timing__setup__ws": 1.25,
    "finish__timing__hold__ws": 0.10,
    "finish__timing__fmax": 400_000_000,
    "finish__timing__drv__max_slew": 0,
    "finish__timing__drv__max_cap": 0,
    "finish__timing__drv__max_fanout": 0,
    "finish__timing__drv__setup_violation_count": 0,
    "finish__timing__drv__hold_violation_count": 0,
    "finish__flow__warnings__count": 0,
    "finish__flow__errors__count": 0,
}


class PhysicalLogCheckTest(unittest.TestCase):
    def test_clean_logs_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_root = Path(temporary_directory)
            (log_root / "clean.log").write_text("[INFO TEST-0001] complete\n", encoding="utf-8")

            self.assertEqual(reported_diagnostics(log_root), [])

    def test_tool_warning_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_root = Path(temporary_directory)
            (log_root / "warning.log").write_text("[WARNING TEST-0002] unsafe condition\n", encoding="utf-8")

            self.assertEqual(reported_diagnostics(log_root), ["warning.log:1: [WARNING TEST-0002] unsafe condition"])

    def test_plain_error_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_root = Path(temporary_directory)
            (log_root / "error.log").write_text("Error: flow failed\n", encoding="utf-8")

            self.assertEqual(reported_diagnostics(log_root), ["error.log:1: Error: flow failed"])

    def test_indented_mixed_case_and_fatal_diagnostics_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_root = Path(temporary_directory)
            (log_root / "diagnostics.log").write_text(
                "  [Warning TEST-1] first\n\tFATAL: second\n [eRrOr TEST-2] third\n",
                encoding="utf-8",
            )

            self.assertEqual(
                reported_diagnostics(log_root),
                [
                    "diagnostics.log:1:   [Warning TEST-1] first",
                    "diagnostics.log:2: \tFATAL: second",
                    "diagnostics.log:3:  [eRrOr TEST-2] third",
                ],
            )

    def test_benign_diagnostic_summary_does_not_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_root = Path(temporary_directory)
            (log_root / "summary.log").write_text("Warnings: 0 Errors: 0 Fatal conditions: 0\n", encoding="utf-8")

            self.assertEqual(reported_diagnostics(log_root), [])

    def test_empty_required_reports_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            report_root = Path(temporary_directory)
            (report_root / "5_route_drc.rpt").write_text("", encoding="utf-8")
            (report_root / "drt_antennas.log").write_text("", encoding="utf-8")
            (report_root / "6_constraint_integrity.rpt").write_text("", encoding="utf-8")

            self.assertEqual(report_failures(report_root), [])

    def test_missing_or_nonempty_report_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            report_root = Path(temporary_directory)
            (report_root / "5_route_drc.rpt").write_text("Short violation\n", encoding="utf-8")

            self.assertEqual(
                report_failures(report_root),
                [
                    "physical report is not empty: 5_route_drc.rpt",
                    "missing required physical report: drt_antennas.log",
                    "missing required physical report: 6_constraint_integrity.rpt",
                ],
            )

    def test_nonempty_detailed_route_report_shard_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            report_root = Path(temporary_directory)
            (report_root / "5_route_drc.rpt").write_text("", encoding="utf-8")
            (report_root / "5_route_drc.rpt-5.rpt").write_text("Short violation\n", encoding="utf-8")
            (report_root / "drt_antennas.log").write_text("", encoding="utf-8")
            (report_root / "6_constraint_integrity.rpt").write_text("", encoding="utf-8")

            self.assertEqual(report_failures(report_root), ["physical report is not empty: 5_route_drc.rpt-5.rpt"])

    def _write_final_evidence(self, root: Path, metrics: dict[str, object] | None = None, report: str = VALID_FINAL_REPORT) -> tuple[Path, Path]:
        log_root = root / "logs"
        report_root = root / "reports"
        log_root.mkdir()
        report_root.mkdir()
        (log_root / "6_report.json").write_text(json.dumps(VALID_FINAL_METRICS if metrics is None else metrics), encoding="utf-8")
        (report_root / "6_finish.rpt").write_text(report, encoding="utf-8")
        return log_root, report_root

    def test_valid_final_timing_and_electrical_evidence_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_root, report_root = self._write_final_evidence(Path(temporary_directory))

            self.assertEqual(final_timing_failures(log_root, report_root), [])

    def test_nonempty_constraint_integrity_report_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            report_root = Path(temporary_directory)
            (report_root / "5_route_drc.rpt").write_text("", encoding="utf-8")
            (report_root / "drt_antennas.log").write_text("", encoding="utf-8")
            (report_root / "6_constraint_integrity.rpt").write_text("unconstrained endpoint response[0]\n", encoding="utf-8")

            self.assertEqual(
                report_failures(report_root),
                ["physical report is not empty: 6_constraint_integrity.rpt"],
            )

    def test_negative_slack_and_nonzero_violation_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            metrics = dict(VALID_FINAL_METRICS)
            metrics["finish__timing__setup__ws"] = -0.25
            metrics["finish__timing__drv__max_cap"] = 1
            report = VALID_FINAL_REPORT.replace("worst slack max 1.25", "worst slack max -0.25").replace("max cap violation count 0", "max cap violation count 1")
            log_root, report_root = self._write_final_evidence(Path(temporary_directory), metrics, report)

            failures = final_timing_failures(log_root, report_root)
            self.assertIn("negative final timing slack finish__timing__setup__ws: -0.25", failures)
            self.assertIn("nonzero final metric finish__timing__drv__max_cap: 1", failures)
            self.assertIn("negative or non-finite final worst slack: -0.25", failures)
            self.assertIn("nonzero final report value max cap violation count: 1", failures)

    def test_duplicate_metric_and_report_value_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            log_root, report_root = self._write_final_evidence(root, report=VALID_FINAL_REPORT + "setup violation count 0\n")
            metrics_path = log_root / "6_report.json"
            metrics_text = metrics_path.read_text(encoding="utf-8")
            metrics_path.write_text(metrics_text[:-1] + ', "finish__timing__fmax": 1}', encoding="utf-8")

            failures = final_timing_failures(log_root, report_root)
            self.assertTrue(any(failure.startswith("invalid final metrics 6_report.json: conflicting duplicate JSON key") for failure in failures))
            self.assertIn("expected exactly one 'setup violation count' value, found 2", failures)

    def test_duplicate_noncritical_orfs_metric_does_not_hide_required_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            log_root, report_root = self._write_final_evidence(root)
            metrics_path = log_root / "6_report.json"
            metrics_text = metrics_path.read_text(encoding="utf-8")
            metrics_path.write_text(metrics_text[:-1] + ', "informational_cell_count": 41, "informational_cell_count": 42}', encoding="utf-8")

            self.assertEqual(final_timing_failures(log_root, report_root), [])


if __name__ == "__main__":
    unittest.main()
