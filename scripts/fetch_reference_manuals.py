#!/usr/bin/env python3
"""Fetch and verify the ignored official architecture-manual cache."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
MANUAL_DIRECTORY = REPOSITORY_ROOT / "references" / "manuals"
MANIFEST_PATH = MANUAL_DIRECTORY / "manifest.json"
MANIFEST_SCHEMA = "m64k.reference-manual-manifest/v2"
PDF_HEADER = b"%PDF-"
PDF_END_MARKER = b"%%EOF"
PDF_TRAILER_SCAN_BYTES = 4096
IDENTITY_SCAN_PAGES = 8


class ManualValidationError(ValueError):
    """Report a malformed manifest or an invalid cached manual."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_text(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value).casefold()
    return " ".join(re.sub(r"[^a-z0-9]+", " ", decomposed).split())


def validate_official_url(field_name: str, value: str) -> None:
    parsed = urllib.parse.urlparse(value)
    hostname = parsed.hostname or ""
    if parsed.scheme != "https" or not (hostname == "nxp.com" or hostname.endswith(".nxp.com")):
        raise ManualValidationError(f"{field_name} must be an HTTPS URL on an official NXP domain: {value}")


def validate_manifest_entry(document: dict[str, Any]) -> None:
    required_strings = (
        "filename",
        "title",
        "document_id",
        "revision",
        "published",
        "url",
        "source_page",
        "sha256",
    )
    missing_fields = [field for field in required_strings if not isinstance(document.get(field), str) or not document[field]]
    if missing_fields:
        raise ManualValidationError(f"manual manifest entry is missing fields: {', '.join(missing_fields)}")

    filename = document["filename"]
    if Path(filename).name != filename or not filename.endswith(".pdf"):
        raise ManualValidationError(f"invalid manual filename: {filename}")

    if re.fullmatch(r"[0-9a-f]{64}", document["sha256"]) is None:
        raise ManualValidationError(f"invalid SHA-256 digest for {filename}")

    page_count = document.get("page_count")
    if not isinstance(page_count, int) or isinstance(page_count, bool) or page_count <= 0:
        raise ManualValidationError(f"page_count must be a positive integer for {filename}")

    identity_markers = document.get("identity_markers")
    if not isinstance(identity_markers, list) or not identity_markers:
        raise ManualValidationError(f"identity_markers must be a non-empty array for {filename}")
    if any(not isinstance(marker, str) or not canonical_text(marker) for marker in identity_markers):
        raise ManualValidationError(f"identity_markers contains an invalid marker for {filename}")

    validate_official_url("url", document["url"])
    validate_official_url("source_page", document["source_page"])


def load_documents() -> list[dict[str, Any]]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if manifest.get("schema") != MANIFEST_SCHEMA:
        raise ManualValidationError(f"unsupported manual manifest schema in {MANIFEST_PATH}")

    documents = manifest.get("documents")
    if not isinstance(documents, list) or not documents:
        raise ManualValidationError("manual manifest must contain a non-empty documents array")

    filenames: set[str] = set()
    document_ids: set[str] = set()
    for document in documents:
        if not isinstance(document, dict):
            raise ManualValidationError("every manual manifest entry must be an object")
        validate_manifest_entry(document)

        if document["filename"] in filenames:
            raise ManualValidationError(f"duplicate manual filename: {document['filename']}")
        if document["document_id"] in document_ids:
            raise ManualValidationError(f"duplicate manual document_id: {document['document_id']}")
        filenames.add(document["filename"])
        document_ids.add(document["document_id"])

    return documents


def require_poppler_tool(program: str) -> str:
    executable = shutil.which(program)
    if executable is None:
        raise ManualValidationError(
            f"required PDF validation tool '{program}' is unavailable; install Fedora package poppler-utils"
        )
    return executable


def run_pdf_tool(command: list[str], document: Path) -> str:
    result = subprocess.run(command, check=False, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        diagnostic = result.stderr.strip() or "no diagnostic"
        raise ManualValidationError(f"PDF parser rejected {document.name}: {diagnostic}")
    if result.stderr.strip():
        raise ManualValidationError(f"PDF parser reported diagnostics for {document.name}: {result.stderr.strip()}")
    return result.stdout


def inspect_pdf(document: Path) -> tuple[int, str]:
    with document.open("rb") as source:
        header = source.read(len(PDF_HEADER))
        if header != PDF_HEADER:
            raise ManualValidationError(f"{document.name} does not start with a PDF signature")

        source.seek(0, os.SEEK_END)
        file_size = source.tell()
        source.seek(max(0, file_size - PDF_TRAILER_SCAN_BYTES))
        if PDF_END_MARKER not in source.read():
            raise ManualValidationError(f"{document.name} does not contain a PDF end marker in its trailer")

    pdfinfo = require_poppler_tool("pdfinfo")
    metadata = run_pdf_tool([pdfinfo, str(document)], document)
    page_match = re.search(r"^Pages:\s+([0-9]+)\s*$", metadata, flags=re.MULTILINE)
    if page_match is None:
        raise ManualValidationError(f"pdfinfo did not report a page count for {document.name}")
    page_count = int(page_match.group(1))
    if page_count <= 0:
        raise ManualValidationError(f"pdfinfo reported an invalid page count for {document.name}: {page_count}")

    pdftotext = require_poppler_tool("pdftotext")
    last_identity_page = min(page_count, IDENTITY_SCAN_PAGES)
    extracted_text = run_pdf_tool(
        [pdftotext, "-f", "1", "-l", str(last_identity_page), "-enc", "UTF-8", "-layout", str(document), "-"],
        document,
    )
    return page_count, canonical_text(extracted_text)


def validation_errors(document: dict[str, Any], path: Path) -> list[str]:
    if not path.is_file():
        return ["file is missing"]

    errors: list[str] = []
    actual_digest = sha256(path)
    if actual_digest != document["sha256"]:
        errors.append(f"SHA-256 mismatch: expected {document['sha256']}, got {actual_digest}")

    try:
        page_count, extracted_text = inspect_pdf(path)
    except (OSError, ManualValidationError) as error:
        errors.append(str(error))
        return errors

    if page_count != document["page_count"]:
        errors.append(f"page-count mismatch: expected {document['page_count']}, got {page_count}")

    for marker in document["identity_markers"]:
        if canonical_text(marker) not in extracted_text:
            errors.append(f"identity marker not found in first {IDENTITY_SCAN_PAGES} pages: {marker!r}")

    return errors


def download(document: dict[str, Any], destination: Path) -> None:
    temporary_path = destination.with_suffix(destination.suffix + ".pending")
    temporary_path.unlink(missing_ok=True)

    try:
        request = urllib.request.Request(document["url"], headers={"User-Agent": "Mozilla/5.0 M64K-reference-fetcher/2"})
        with urllib.request.urlopen(request) as response, temporary_path.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())

        errors = validation_errors(document, temporary_path)
        if errors:
            raise ManualValidationError(f"downloaded {document['filename']} is invalid: {'; '.join(errors)}")
        os.replace(temporary_path, destination)
    finally:
        temporary_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the local cache without downloading")
    arguments = parser.parse_args()

    try:
        documents = load_documents()
    except (OSError, json.JSONDecodeError, ManualValidationError) as error:
        print(f"ERROR {error}", file=sys.stderr)
        return 1

    MANUAL_DIRECTORY.mkdir(parents=True, exist_ok=True)
    failed = False

    for document in documents:
        destination = MANUAL_DIRECTORY / document["filename"]
        errors = validation_errors(document, destination)
        if not errors:
            print(f"OK {document['document_id']}: {destination}")
            continue

        if arguments.check:
            print(f"ERROR {document['document_id']}: {destination}: {'; '.join(errors)}", file=sys.stderr)
            failed = True
            continue

        print(f"FETCH {document['document_id']}: {document['url']}")
        try:
            download(document, destination)
        except (OSError, ManualValidationError) as error:
            print(f"ERROR {document['document_id']}: {error}", file=sys.stderr)
            failed = True
            continue
        print(f"OK {document['document_id']}: {destination}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
