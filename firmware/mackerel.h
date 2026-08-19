#ifndef MACKEREL_H
#define MACKEREL_H

#include <stdbool.h>
#include <stdint.h>
#include "mem.h"

#define SYSTEM_NAME "Mackerel 68000 SoC"

#define EXCEPTION_AUTOVECTOR 24
#define EXCEPTION_USER 64
#define IRQ_NUM_UART 5
#define IRQ_NUM_TIMER 6

#define GPIO_BASE   0xFFF800UL
#define UART_BASE   0xFFF900UL
#define TIMER_BASE  0xFFFA00UL
#define SPI_BASE    0xFFFB00UL
#define SPI2_BASE   0xFFFC00UL
#define INTC_BASE   0xFFFD00UL
#define WS2812_BASE 0xFFFE00UL

#define PROGRAM_START 0x400UL
#define CPU_CLK_HZ 37800000UL
#define SLEEP_CYCLES_PER_LOOP 40

void set_interrupts(bool enabled);
void set_exception_handler(unsigned char exception_number,
                           void (*exception_handler)(void));
void memdump(uint32_t address, uint32_t bytes);
uint16_t bswap16(uint16_t value);
uint32_t bswap32(uint32_t value);
void sleep_us(uint32_t us);
void sleep_ms(uint32_t ms);
void delay(int time);

#endif
