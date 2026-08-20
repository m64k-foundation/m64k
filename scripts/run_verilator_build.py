#!/usr/bin/env python3
"""Publish a Verilator test executable only after a successful, valid build."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import stat
import subprocess
import sys


ELF_MAGIC = b"\x7fELF"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()

    if arguments.command and arguments.command[0] == "--":
        arguments.command = arguments.command[1:]

    if not arguments.command:
        parser.error("a Verilator build command is required after --")

    return arguments


def validate_pending_executable(path: Path) -> None:
    if not path.is_file():
        raise RuntimeError(f"Verilator did not produce the pending executable: {path}")

    if path.stat().st_size < len(ELF_MAGIC):
        raise RuntimeError(f"Verilator produced a truncated executable: {path}")

    with path.open("rb") as executable_file:
        if executable_file.read(len(ELF_MAGIC)) != ELF_MAGIC:
            raise RuntimeError(f"Verilator output is not an ELF executable: {path}")

    executable_mode = path.stat().st_mode
    if executable_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH) == 0:
        raise RuntimeError(f"Verilator output is not executable: {path}")


def synchronize_file(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def synchronize_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main() -> int:
    arguments = parse_arguments()
    output = arguments.output.resolve()
    pending_output = output.with_name(f"{output.name}.pending")

    output.parent.mkdir(parents=True, exist_ok=True)
    pending_output.unlink(missing_ok=True)

    try:
        completed = subprocess.run(arguments.command, check=False)
        if completed.returncode != 0:
            return completed.returncode

        validate_pending_executable(pending_output)
        synchronize_file(pending_output)
        os.replace(pending_output, output)
        synchronize_directory(output.parent)
    except (OSError, RuntimeError) as error:
        print(f"atomic Verilator publication failed: {error}", file=sys.stderr)
        return 1
    finally:
        pending_output.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
