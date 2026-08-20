#!/usr/bin/env python3
"""Run one command in the immutable M64K ASIC tool container."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = REPOSITORY_ROOT / "containers/asic/tool-lock.json"
IMMUTABLE_IMAGE = re.compile(r"^[^\s]+@sha256:[0-9a-f]{64}$")
ISO_DATE = re.compile(r"^20[0-9]{2}-[01][0-9]-[0-3][0-9]$")


def locked_image() -> str:
    with LOCK_PATH.open(encoding="utf-8") as lock_file:
        lock = json.load(lock_file)

    expected_fields = {"schema_version", "image", "informational_source_tag", "resolved_on", "verified_on", "platform", "observed_tools", "purpose"}
    if set(lock) != expected_fields or lock.get("schema_version") != 1:
        raise ValueError(f"{LOCK_PATH} does not implement the exact supported lock schema")
    if lock.get("platform") != "linux/amd64":
        raise ValueError(f"{LOCK_PATH} selects unsupported platform {lock.get('platform')!r}")
    if not all(isinstance(lock.get(field), str) and lock[field].strip() for field in ("informational_source_tag", "purpose")):
        raise ValueError(f"{LOCK_PATH} contains invalid descriptive metadata")
    if not all(isinstance(lock.get(field), str) and ISO_DATE.fullmatch(lock[field]) for field in ("resolved_on", "verified_on")):
        raise ValueError(f"{LOCK_PATH} contains invalid ISO date metadata")
    observed_tools = lock.get("observed_tools")
    if not isinstance(observed_tools, dict) or set(observed_tools) != {"yosys", "openroad", "opensta"}:
        raise ValueError(f"{LOCK_PATH} contains invalid observed tool metadata")
    if any(not isinstance(version, str) or not version.strip() for version in observed_tools.values()):
        raise ValueError(f"{LOCK_PATH} contains an empty observed tool version")

    image = lock.get("image")
    if not isinstance(image, str) or not IMMUTABLE_IMAGE.fullmatch(image):
        raise ValueError(f"{LOCK_PATH} does not contain an immutable OCI image digest")

    return image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--print-image", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()

    try:
        image = locked_image()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ASIC tool lock error: {error}", file=sys.stderr)
        return 2

    if arguments.print_image:
        print(image)
        return 0

    command = arguments.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("a container command is required unless --print-image is used")

    build_directory = REPOSITORY_ROOT / "build"
    build_directory.mkdir(exist_ok=True)
    if build_directory.is_symlink() or build_directory.resolve() != build_directory:
        raise ValueError(f"{build_directory} must be a real repository-local directory, not a symlink")

    docker_command = [
        "docker",
        "run",
        "--rm",
        "--network",
        "none",
        "--platform",
        "linux/amd64",
        "--user",
        f"{os.getuid()}:{os.getgid()}",
        "--volume",
        f"{REPOSITORY_ROOT}:/workspace:ro",
        "--volume",
        f"{build_directory}:/workspace/build:rw",
        "--tmpfs",
        "/tmp:rw,nosuid,nodev",
        "--workdir",
        "/workspace",
        image,
        *command,
    ]
    return subprocess.run(docker_command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
