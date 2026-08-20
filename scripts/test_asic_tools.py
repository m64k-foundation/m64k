#!/usr/bin/env python3
"""Tests for immutable ASIC tooling configuration and source gates."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_CHECK = ROOT / "scripts/check_asic_manifest.py"
WARNING_CHECK = ROOT / "scripts/check_yosys_log.py"
CONTAINER_RUNNER = ROOT / "scripts/run_asic_container.py"
QOR_SUMMARY = ROOT / "scripts/summarize_yosys_stat.py"
EQUIV_SUMMARY = ROOT / "scripts/summarize_yosys_equivalence.py"
PRODUCTION_SOURCE = "rtl/core/execute/integer/m64k_integer_alu_pkg.sv"


class AsicToolTests(unittest.TestCase):
    def run_script(self, script: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(script), *arguments],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

    def check_manifest_text(self, contents: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "target.f"
            manifest.write_text(contents, encoding="utf-8")
            return self.run_script(MANIFEST_CHECK, str(manifest))

    def test_locked_image_is_an_immutable_digest(self) -> None:
        completed = self.run_script(CONTAINER_RUNNER, "--print-image")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        image = completed.stdout.strip()
        self.assertIn("@sha256:", image)
        self.assertEqual(len(image.rsplit("@sha256:", 1)[1]), 64)

        lock = json.loads((ROOT / "containers/asic/tool-lock.json").read_text(encoding="utf-8"))
        self.assertEqual(image, lock["image"])
        self.assertEqual(lock["platform"], "linux/amd64")

    def test_manifest_accepts_first_party_rtl(self) -> None:
        completed = self.check_manifest_text(f"{PRODUCTION_SOURCE}\n")
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_manifest_rejects_non_rtl_and_duplicate_sources(self) -> None:
        forbidden = self.check_manifest_text("verification/rtl/m64k_integer_alu_tb.sv\n")
        self.assertNotEqual(forbidden.returncode, 0)

        duplicate = self.check_manifest_text(f"{PRODUCTION_SOURCE}\n{PRODUCTION_SOURCE}\n")
        self.assertNotEqual(duplicate.returncode, 0)

    def test_manifest_rejects_traversal_and_missing_sources(self) -> None:
        traversal = self.check_manifest_text("../outside.sv\n")
        self.assertNotEqual(traversal.returncode, 0)

        missing = self.check_manifest_text("rtl/does-not-exist.sv\n")
        self.assertNotEqual(missing.returncode, 0)

    def test_manifest_rejects_shell_metacharacters(self) -> None:
        injected = self.check_manifest_text('rtl/core/execute/integer/not-real";touch build/injected;.sv\n')
        self.assertNotEqual(injected.returncode, 0)
        self.assertIn("portable", injected.stderr)

    def test_warning_gate_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            clean_log = Path(directory) / "clean.log"
            clean_log.write_text("No problems found\n", encoding="utf-8")
            self.assertEqual(self.run_script(WARNING_CHECK, str(clean_log)).returncode, 0)

            warning_log = Path(directory) / "warning.log"
            warning_log.write_text("Warning: first-party width mismatch\n", encoding="utf-8")
            self.assertNotEqual(self.run_script(WARNING_CHECK, str(warning_log)).returncode, 0)

    def test_qor_summary_revalidates_its_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            statistics = temporary / "stat.json"
            manifest = temporary / "target.f"
            tool_lock = temporary / "tool-lock.json"
            flow = temporary / "flow.ys"
            netlist = temporary / "netlist.v"
            log = temporary / "synthesis.log"
            output = temporary / "qor.json"

            statistics.write_text('{"modules":{"top":{"num_cells":0}}}\n', encoding="utf-8")
            manifest.write_text("../outside.sv\n", encoding="utf-8")
            tool_lock.write_text('{"image":"invalid-for-this-negative-test"}\n', encoding="utf-8")
            flow.write_text("# test flow\n", encoding="utf-8")
            netlist.write_text("module top; endmodule\n", encoding="utf-8")
            log.write_text("No problems found\n", encoding="utf-8")

            completed = self.run_script(
                QOR_SUMMARY,
                "--stat", str(statistics),
                "--manifest", str(manifest),
                "--tool-lock", str(tool_lock),
                "--flow", str(flow),
                "--netlist", str(netlist),
                "--log", str(log),
                "--target", "negative_test",
                "--top", "top",
                "--output", str(output),
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("QoR summary error", completed.stderr)
            self.assertFalse(output.exists())

    def test_equivalence_summary_requires_an_exact_success_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            reference_manifest = temporary / "reference.f"
            candidate_manifest = temporary / "candidate.f"
            candidate_netlist = temporary / "candidate.v"
            miter = temporary / "miter.sv"
            tool_lock = temporary / "tool-lock.json"
            flow = temporary / "flow.ys"
            proof_log = temporary / "proof.log"
            output = temporary / "equivalence.json"

            reference_manifest.write_text(f"{PRODUCTION_SOURCE}\n", encoding="utf-8")
            candidate_manifest.write_text(f"{PRODUCTION_SOURCE}\n", encoding="utf-8")
            candidate_netlist.write_text("module candidate; endmodule\n", encoding="utf-8")
            miter.write_text("module miter; endmodule\n", encoding="utf-8")
            tool_lock.write_text('{"image":"immutable-test-image@sha256:00"}\n', encoding="utf-8")
            flow.write_text("# test flow\n", encoding="utf-8")

            arguments = (
                "--log", str(proof_log),
                "--reference-manifest", str(reference_manifest),
                "--candidate-manifest", str(candidate_manifest),
                "--candidate-netlist", str(candidate_netlist),
                "--miter", str(miter),
                "--tool-lock", str(tool_lock),
                "--flow", str(flow),
                "--target", "test_equivalence",
                "--output", str(output),
            )

            proof_log.write_text("SAT proof did not complete\n", encoding="utf-8")
            failed = self.run_script(EQUIV_SUMMARY, *arguments)
            self.assertNotEqual(failed.returncode, 0)
            self.assertFalse(output.exists())

            proof_log.write_text("SAT proof finished - no model found: SUCCESS!\n", encoding="utf-8")
            completed = self.run_script(EQUIV_SUMMARY, *arguments)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            summary = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(summary["result"], "proven")
            self.assertEqual(summary["engine"], "Yosys internal MiniSAT")


if __name__ == "__main__":
    unittest.main()
