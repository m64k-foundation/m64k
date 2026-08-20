#!/usr/bin/env python3
"""Focused tests for the architecture-manual cache validator."""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import fetch_reference_manuals as manuals


def manifest_entry(filename: str = "TEST.pdf") -> dict[str, object]:
    return {
        "filename": filename,
        "title": "Test Manual",
        "document_id": "TESTUM",
        "revision": "1",
        "published": "2026-08-20",
        "url": "https://cache.nxp.com/docs/en/reference-manual/TEST.pdf",
        "source_page": "https://www.nxp.com/products/TEST",
        "sha256": hashlib.sha256(b"manual").hexdigest(),
        "page_count": 4,
        "identity_markers": ["Test User's Manual"],
    }


class CanonicalTextTests(unittest.TestCase):
    def test_normalizes_case_whitespace_and_typographic_punctuation(self) -> None:
        self.assertEqual(manuals.canonical_text(" User’s\nMANUAL "), "user s manual")
        self.assertEqual(manuals.canonical_text("User's Manual"), "user s manual")


class ManifestValidationTests(unittest.TestCase):
    def test_rejects_non_official_download_url(self) -> None:
        document = manifest_entry()
        document["url"] = "https://example.com/TEST.pdf"

        with self.assertRaisesRegex(manuals.ManualValidationError, "official NXP domain"):
            manuals.validate_manifest_entry(document)

    def test_rejects_boolean_page_count(self) -> None:
        document = manifest_entry()
        document["page_count"] = True

        with self.assertRaisesRegex(manuals.ManualValidationError, "positive integer"):
            manuals.validate_manifest_entry(document)

    def test_rejects_duplicate_document_identity(self) -> None:
        first = manifest_entry("FIRST.pdf")
        second = manifest_entry("SECOND.pdf")
        manifest = {"schema": manuals.MANIFEST_SCHEMA, "documents": [first, second]}

        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with mock.patch.object(manuals, "MANIFEST_PATH", manifest_path):
                with self.assertRaisesRegex(manuals.ManualValidationError, "duplicate manual document_id"):
                    manuals.load_documents()


class PdfValidationTests(unittest.TestCase):
    def test_rejects_html_before_invoking_pdf_tools(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            document = Path(directory) / "error.pdf"
            document.write_text("<!doctype html><title>Access denied</title>", encoding="utf-8")

            with mock.patch.object(manuals, "require_poppler_tool") as require_tool:
                with self.assertRaisesRegex(manuals.ManualValidationError, "does not start with a PDF signature"):
                    manuals.inspect_pdf(document)
            require_tool.assert_not_called()

    def test_rejects_truncated_pdf_before_invoking_pdf_tools(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            document = Path(directory) / "truncated.pdf"
            document.write_bytes(b"%PDF-1.7\ntruncated body")

            with mock.patch.object(manuals, "require_poppler_tool") as require_tool:
                with self.assertRaisesRegex(manuals.ManualValidationError, "does not contain a PDF end marker"):
                    manuals.inspect_pdf(document)
            require_tool.assert_not_called()

    def test_reports_digest_page_count_and_identity_independently(self) -> None:
        document = manifest_entry()

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "TEST.pdf"
            path.write_bytes(b"different content")
            with mock.patch.object(manuals, "inspect_pdf", return_value=(3, "different manual")):
                errors = manuals.validation_errors(document, path)

        self.assertTrue(any("SHA-256 mismatch" in error for error in errors))
        self.assertTrue(any("page-count mismatch" in error for error in errors))
        self.assertTrue(any("identity marker not found" in error for error in errors))

    def test_accepts_matching_digest_page_count_and_identity(self) -> None:
        document = manifest_entry()

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "TEST.pdf"
            path.write_bytes(b"manual")
            with mock.patch.object(manuals, "inspect_pdf", return_value=(4, "test user s manual")):
                errors = manuals.validation_errors(document, path)

        self.assertEqual(errors, [])

    def test_rejects_parser_diagnostics_even_when_exit_status_is_zero(self) -> None:
        completed_process = mock.Mock(returncode=0, stdout="Pages: 4\n", stderr="Syntax Warning: damaged xref")

        with mock.patch.object(manuals.subprocess, "run", return_value=completed_process):
            with self.assertRaisesRegex(manuals.ManualValidationError, "reported diagnostics"):
                manuals.run_pdf_tool(["pdfinfo", "TEST.pdf"], Path("TEST.pdf"))


if __name__ == "__main__":
    unittest.main()
