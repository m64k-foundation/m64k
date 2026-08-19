#ifndef _SPI_TINY_H
#define _SPI_TINY_H

#include "mackerel.h"

// tiny_spi registers use the SoC's x4 byte stride.
#define SPI_RXDATA (SPI_BASE + 0)
#define SPI_TXDATA (SPI_BASE + 4)
#define SPI_STATUS (SPI_BASE + 8)
#define SPI_CONTROL (SPI_BASE + 12)
#define SPI_BAUD (SPI_BASE + 16)

// STATUS bits
#define SPI_TXE 0x01 // engine idle (transfer complete)
#define SPI_TXR 0x02 // ready to accept the next byte

void spi_init(uint8_t baud);
uint8_t spi_transfer(uint8_t tx);

#endif
