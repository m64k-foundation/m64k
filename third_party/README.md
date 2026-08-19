# Third-party RTL

The following upstream revisions were used when this directory was vendored:

| Component | Upstream | Revision | License |
|---|---|---|---|
| fx68k | https://github.com/ijor/fx68k | `0602ee4` | GPLv3 |
| uart16550 | https://github.com/freecores/uart16550 | `2b0ad80` | Notice in source |
| tiny_spi | https://github.com/freecores/tiny_spi | `562bf1f` | Notice in source |
| SDRAM controller | https://github.com/nand2mario/sdram-tang-nano-20k | `918ae41` | MIT |

Only files required to build this SoC are retained. Run `scripts/fetch-cores.sh`
into an empty `third_party/` directory when a complete upstream checkout is needed.
