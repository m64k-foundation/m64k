# Architecture reference-manual cache

This directory is the persistent local cache for official architecture manuals used by M64K semantic-lineage reviews. The PDFs are copyrighted primary-source material and are intentionally ignored by Git. The tracked `manifest.json` records the exact official URL, catalog page, document identity, revision, SHA-256 digest, parsed page count, and required identity markers accepted by the project.

The cache covers the MC68060 semantic baseline, its addendum and production errata, the family programmer's reference manual and errata, and the MC68000, MC68020, MC68030, and MC68040 manuals needed when the MC68060 documentation delegates behavior to an earlier generation. Applicable MC68020 and MC68040 manual corrections are included as separate documents.

Fetch missing documents and verify every cached file with:

```sh
python3 scripts/fetch_reference_manuals.py
```

Verify the cache without network access:

```sh
python3 scripts/fetch_reference_manuals.py --check
```

Validation requires `pdfinfo` and `pdftotext` from Poppler. On Fedora, install them with:

```sh
sudo dnf install poppler-utils
```

The check does not trust a digest alone. It requires a PDF header and trailer, successful parser execution, the exact expected page count, the expected SHA-256 digest, and document-specific text markers. An NXP error page or a truncated response therefore cannot become an accepted reference merely by recording its digest.

An instruction or system-contract review cites the manual identity, revision, section, and page range in the machine-readable lineage record. Possession of a PDF does not make its behavior normative M64K behavior and does not grant redistribution rights.
