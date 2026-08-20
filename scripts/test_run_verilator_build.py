from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
RUNNER = REPOSITORY_ROOT / "scripts" / "run_verilator_build.py"


class AtomicVerilatorBuildTests(unittest.TestCase):
    def run_runner(self, output: Path, command: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(RUNNER), "--output", str(output), "--", *command],
            check=False,
            capture_output=True,
            text=True,
        )

    def create_executable(self, path: Path, contents: bytes = b"\x7fELFvalid") -> None:
        path.write_bytes(contents)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def test_success_atomically_replaces_previous_executable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "Vtest"
            pending = output.with_name("Vtest.pending")
            self.create_executable(output, b"\x7fELFold")

            command = ["cp", "/bin/true", str(pending)]
            completed = self.run_runner(output, command)

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(output.read_bytes()[:4], b"\x7fELF")
            self.assertFalse(pending.exists())

    def test_failed_command_preserves_previous_executable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "Vtest"
            original = b"\x7fELFprevious"
            self.create_executable(output, original)

            completed = self.run_runner(output, ["/bin/false"])

            self.assertNotEqual(completed.returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            self.assertFalse(output.with_name("Vtest.pending").exists())

    def test_invalid_success_output_preserves_previous_executable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "Vtest"
            pending = output.with_name("Vtest.pending")
            original = b"\x7fELFprevious"
            self.create_executable(output, original)

            command = ["touch", str(pending)]
            completed = self.run_runner(output, command)

            self.assertNotEqual(completed.returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            self.assertFalse(pending.exists())


if __name__ == "__main__":
    unittest.main()
