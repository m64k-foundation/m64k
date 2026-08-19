# Local development tools

This directory is the stable project-local home for downloaded and extracted
development tools:

```text
tools/downloads/   cached source/toolchain archives
tools/toolchains/  extracted cross-compilers
```

Both subdirectories are intentionally ignored by Git because their contents
are large, host-specific and reproducible. Buildable toolchain definitions and
source patches remain versioned in `toolchain/`; project utilities remain in
`scripts/`.

The expected bare-metal compiler layout is:

```text
tools/toolchains/m68k-mackerel-elf/bin/m68k-mackerel-elf-gcc
```

The root Makefile detects this location automatically. `M68K_CROSS` can still
select another installation explicitly.
