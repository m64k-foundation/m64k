#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include "mackerel.h"
#include "console.h"
#include "term.h"
#include "ymodem.h"

#include "fat16.h"
#include "sd_spi.h"
#include "uart.h"
#include "ws2812.h"
#include "netboot.h"

#define VERSION "0.10.0"

#define INPUT_BUFFER_SIZE 32

void handler_run(uint32_t addr);
void handler_ymodem(uint32_t addr);
void handler_zero(uint32_t addr, uint32_t size);
void handler_boot();
static void autoboot(void);
void handler_rgb(char *r_str, char *g_str, char *b_str);
void handler_gpio(char *arg1, char *arg2, char *arg3);
void handler_help();
void handler_info();
uint8_t readline(char *buffer);
void command_not_found(char *command);
void memdump(uint32_t address, uint32_t bytes);
void print_string_bin(char *str, uint8_t max);

void memtest8(uint8_t *start, uint32_t size, uint8_t target);
void memtest16(uint16_t *start, uint32_t size, uint16_t target);
void memtest32(uint32_t *start, uint32_t size);


// Reference RAM info from the linker script
extern char __sram_start[];
extern char __sram_length[];
extern char __dram_start[];
extern char __dram_length[];

char buffer[INPUT_BUFFER_SIZE];


void handler_help()
{
    printf("Available commands:\r\n");
    printf(" ymodem <addr>         - Receive a file via YMODEM into RAM at <addr> (default 0x%lX)\r\n", PROGRAM_START);
    printf(" boot                  - Load Linux (IMAGE.BIN) from disk and run\r\n");
    printf(" netboot               - Fetch an image over Ethernet (W5500) and run\r\n");
    printf(" run                   - Jump to RAM at 0x%lX\r\n", PROGRAM_START);
    printf(" dump <addr>           - Dump 256 bytes of memory starting at <addr>\r\n");
    printf(" peek <addr>           - Peek a byte from memory at <addr>\r\n");
    printf(" poke <addr> <val>     - Poke a byte <val> into memory at <addr>\r\n");
    printf(" mem8 <start> <size>   - Run 8-bit memory test from <start> for <size> bytes\r\n");
    printf(" mem16 <start> <size>  - Run 16-bit memory test from <start> for <size> bytes\r\n");
    printf(" mem32 <start> <size>  - Run 32-bit memory test from <start> for <size> bytes\r\n");
    printf(" zero <start> <size>   - Zero out memory from <start> for <size> bytes\r\n");
    printf(" gpio [<led> <0|1>]    - Show GPIO reg, or set LED 0-5 (1=on)\r\n");
    printf(" rgb <r> <g> <b>       - Set the onboard WS2812 RGB LED (0-255 each)\r\n");
    printf(" info                  - Show system information\r\n");
    printf(" help                  - Show this help message\r\n");
}

int main()
{
    // Re-enable the cursor in case a reset interrupted a transfer that had
    // hidden it while drawing the progress bar (see fat16/sd read loops).
    term_cursor_set_vis(true);

    console_puts("\r\n");
    console_puts("========================================\r\n");
    console_puts("   " SYSTEM_NAME " Bootloader v" VERSION "\r\n");
    console_puts("   Build Date: " __DATE__ " - " __TIME__ "\r\n");
    console_puts("   Copyright (c) 2026 Colin Maykish\r\n");
    console_puts("   github.com/crmaykish/mackerel-68k\r\n");
    console_puts("========================================\r\n\r\n");

    // Auto-boot Linux from the SD card after a short, cancellable countdown.
    autoboot();

    console_puts("Type 'help' for a list of available commands.\r\n\r\n");

    while (true)
    {
        // Present the command prompt and wait for input
        console_puts("> ");
        readline(buffer);
        console_puts("\r\n");

        if (strncmp(buffer, "ymodem", 6) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            uint32_t addr = strtoul(param1, 0, 16);
            handler_ymodem(addr);
        }
        else if (strncmp(buffer, "boot", 4) == 0)
        {
            handler_boot();
        }
        else if (strncmp(buffer, "netboot", 7) == 0)
        {
            if (netboot_load())
                handler_run(PROGRAM_START);
        }
        else if (strncmp(buffer, "run", 3) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            uint32_t addr = strtoul(param1, 0, 16);
            handler_run(addr);
        }
        else if (strncmp(buffer, "dump", 4) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            uint32_t addr = strtoul(param1, 0, 16);

            memdump(addr, 256);
        }
        else if (strncmp(buffer, "peek", 4) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            uint32_t addr = strtoul(param1, 0, 16);

            printf("%02X", MEM(addr));
        }
        else if (strncmp(buffer, "poke", 4) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            char *param2 = strtok(NULL, " ");
            uint32_t addr = strtoul(param1, 0, 16);
            uint8_t val = (uint8_t)strtoul(param2, 0, 16);

            MEM(addr) = val;
        }
        else if (strncmp(buffer, "mem8", 4) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            char *param2 = strtok(NULL, " ");
            uint32_t start = strtoul(param1, 0, 16);
            uint32_t size = strtoul(param2, 0, 16);

            memtest8((uint8_t *)start, size, 0x00);
            memtest8((uint8_t *)start, size, 0xAA);
            memtest8((uint8_t *)start, size, 0x55);
            memtest8((uint8_t *)start, size, 0xFF);

            printf("Test complete\r\n");
        }
        else if (strncmp(buffer, "mem16", 4) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            char *param2 = strtok(NULL, " ");
            uint32_t start = strtoul(param1, 0, 16);
            uint32_t size = strtoul(param2, 0, 16);

            memtest16((uint16_t *)start, size, 0x0000);
            memtest16((uint16_t *)start, size, 0xAABB);
            memtest16((uint16_t *)start, size, 0x55CC);
            memtest16((uint16_t *)start, size, 0xFFFF);

            printf("Test complete\r\n");
        }
        else if (strncmp(buffer, "mem32", 5) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            char *param2 = strtok(NULL, " ");
            uint32_t start = strtoul(param1, 0, 16);
            uint32_t size = strtoul(param2, 0, 16);
            memtest32((uint32_t *)start, size);
        }
        else if (strncmp(buffer, "zero", 4) == 0)
        {
            strtok(buffer, " ");
            char *param1 = strtok(NULL, " ");
            char *param2 = strtok(NULL, " ");
            uint32_t start = strtoul(param1, 0, 16);
            uint32_t size = strtoul(param2, 0, 16);
            handler_zero(start, size);
        }
        else if (strncmp(buffer, "gpio", 4) == 0)
        {
            strtok(buffer, " ");
            char *arg1 = strtok(NULL, " ");
            char *arg2 = strtok(NULL, " ");
            char *arg3 = strtok(NULL, " ");
            handler_gpio(arg1, arg2, arg3);
        }
        else if (strncmp(buffer, "rgb", 3) == 0)
        {
            strtok(buffer, " ");
            char *r = strtok(NULL, " ");
            char *g = strtok(NULL, " ");
            char *b = strtok(NULL, " ");
            handler_rgb(r, g, b);
        }
        else if (strncmp(buffer, "info", 4) == 0)
        {
            handler_info();
        }
        else if (strncmp(buffer, "help", 4) == 0)
        {
            handler_help();
        }
        else
        {
            command_not_found(buffer);
        }

        console_puts("\r\n");
    }

    return 0;
}

// Six LEDs share the GPIO register with the SD and NIC chip selects.
void handler_gpio(char *num_str, char *val_str, char *unused)
{
    (void)unused;

    if (!num_str)
    {
        printf("GPIO = 0x%02X\r\n", MEM(GPIO_BASE));
        return;
    }
    if (!val_str)
    {
        printf("Usage: gpio [<led 0-5> <0|1>]\r\n");
        return;
    }

    uint8_t led = (uint8_t)strtoul(num_str, 0, 10);
    if (led > 5)
    {
        printf("LEDs are 0-5\r\n");
        return;
    }

    // Set the bit to light the LED, clear it to turn it off
    // The read-modify-write preserves the other LEDs and the CS bits (6-7)
    uint8_t reg = MEM(GPIO_BASE);
    if (*val_str == '1')
        reg |= (1 << led);
    else
        reg &= ~(1 << led);
    MEM(GPIO_BASE) = reg;
    printf("GPIO = 0x%02X\r\n", reg);
}
// Set the onboard WS2812 RGB LED. Each value is 0-255, decimal or 0x hex.
void handler_rgb(char *r_str, char *g_str, char *b_str)
{
    if (!r_str || !g_str || !b_str)
    {
        printf("Usage: rgb <r> <g> <b>  (0-255 each, decimal or 0x)\r\n");
        return;
    }

    uint8_t r = (uint8_t)strtoul(r_str, 0, 0);
    uint8_t g = (uint8_t)strtoul(g_str, 0, 0);
    uint8_t b = (uint8_t)strtoul(b_str, 0, 0);
    ws2812_set(r, g, b);
    printf("RGB = %u %u %u\r\n", r, g, b);
}

void handler_run(uint32_t addr)
{
    if (addr == 0)
    {
        addr = PROGRAM_START;
    }

    printf("Jumping to 0x%lX\r\n", addr);

    // Jump to the subroutine at the specified address
    // Programs will return control to the bootloader when they exit because jsr is used
    __asm__ volatile(
        "move.l %0, %%a0\n\t"
        "jsr (%%a0)"
        :
        : "r"(addr)
        : "a0");
}

static int block_read(uint32_t block_num, uint8_t *block, uint32_t count)
{
    return sd_spi_read(block_num, block, count);
}

static int load_named_file(fat16_boot_sector_t *bs, fat16_dir_entry_t *files,
                           const char *name12, uint32_t addr)
{
    for (int i = 0; i < 16; i++)
    {
        if (files[i].file_size == 0)
            continue;

        char filename[13];
        fat16_get_file_name(&files[i], filename);

        if (strncmp(filename, name12, 12) != 0)
            continue;

        printf("\r\nReading %s (%ld bytes) into RAM at 0x%lX...\r\n",
               name12, files[i].file_size, (unsigned long)addr);

        int n = fat16_read_file(bs, files[i].first_cluster_low,
                                (uint8_t *)addr, files[i].file_size);

        if (n != (int)files[i].file_size)
        {
            printf("Read failed (%d of %ld bytes)\r\n", n, files[i].file_size);
            return -1;
        }

        printf("Read %d bytes OK\r\n", n);
        return n;
    }

    return -1; // not found
}

void handler_boot()
{
    fat16_boot_sector_t boot_sector;
    fat16_dir_entry_t files_list[16] = {0};

    printf("Loading IMAGE.BIN from SD card...\r\n");

    if (!sd_spi_init())
    {
        printf("SD init failed\r\n");
        return;
    }
    sd_spi_print_info();

    // Initialize FAT16 library with the board's block read function
    if (fat16_init(block_read) != 0)
    {
        printf("Failed to initialize FAT16 library\r\n");
        return;
    }

    fat16_read_boot_sector(2048, &boot_sector);
    fat16_print_boot_sector_info(&boot_sector);

    printf("\r\nReading files on disk...\r\n");
    fat16_list_files(&boot_sector, files_list);

    // Load the kernel image (the ROMfs root is appended inside IMAGE.BIN)
    if (load_named_file(&boot_sector, files_list, "IMAGE   .BIN", PROGRAM_START) < 0)
    {
        printf("ERROR: Could not load IMAGE.BIN from disk\r\n");
        return;
    }

    handler_run(PROGRAM_START);
}

static void leds_show(uint8_t mask)
{
    MEM(GPIO_BASE) = (MEM(GPIO_BASE) & 0xC0) | (mask & 0x3F);
}

// Auto-boot Linux from the SD card after a ~5 s countdown unless a key is pressed
static void autoboot(void)
{
    fat16_boot_sector_t bs;
    fat16_dir_entry_t files[16] = {0};

    // Bring up the SD + FAT and look for IMAGE.BIN
    if (!sd_spi_init())
        return;
    if (fat16_init(block_read) != 0)
        return;
    fat16_read_boot_sector(2048, &bs);
    fat16_list_files(&bs, files);

    bool have_image = false;
    for (int i = 0; i < 16; i++)
    {
        if (files[i].file_size == 0)
            continue;
        char fn[13];
        fat16_get_file_name(&files[i], fn);
        if (strncmp(fn, "IMAGE   .BIN", 12) == 0)
        {
            have_image = true;
            break;
        }
    }
    if (!have_image)
        return;

    printf("SD card detected with IMAGE.BIN.\r\n");
    printf("Auto-booting in 5 seconds -- press any key to cancel...\r\n");

    // Single lit LED walking position 0 - 5
    for (int pos = 0; pos < 6; pos++)
    {
        leds_show(1 << pos);
        for (int slice = 0; slice < 55; slice++)
        {
            if (uart_rx_ready())
            {
                while (uart_rx_ready()) // drain the cancel key(s)
                    (void)uart_getc();
                leds_show(0x00); // all off
                printf("Autoboot cancelled.\r\n");
                return;
            }
            sleep_ms(10);
        }
    }

    // Countdown finished uninterrupted - boot
    leds_show(0x3F); // all on
    printf("Auto-booting...\r\n");

    if (load_named_file(&bs, files, "IMAGE   .BIN", PROGRAM_START) < 0)
    {
        printf("ERROR: Could not load IMAGE.BIN\r\n");
        leds_show(0x00);
        return;
    }

    handler_run(PROGRAM_START);
}

void handler_ymodem(uint32_t addr)
{
    static char name[128];
    uint32_t size = 0;

    if (addr == 0) {
        addr = PROGRAM_START;
    }

    uint32_t bufsz = 0x800000; // 8 MiB system RAM

    printf("Ready to receive at 0x%lx over YMODEM...\r\n", (unsigned long)addr);

    long n = ymodem_recv((uint8_t *)addr, bufsz, name, &size);

    if (n < 0)
    {
        printf("\r\nYMODEM transfer failed (%ld).\r\n", n);
        return;
    }

    printf("\r\nReceived '%s' (%ld bytes) into 0x%lx.\r\n", name, n, (unsigned long)addr);

    if (size && (uint32_t)n != size)
    {
        printf("Warning: stored %ld of %lu bytes (buffer limit?).\r\n", n, (unsigned long)size);
    }
}

void handler_zero(uint32_t addr, uint32_t size)
{
    uint32_t *p = (uint32_t *)addr;
    uint32_t n = size / 4;

    // Unroll 8 stores per loop for speed
    while (n >= 8)
    {
        p[0] = 0;
        p[1] = 0;
        p[2] = 0;
        p[3] = 0;
        p[4] = 0;
        p[5] = 0;
        p[6] = 0;
        p[7] = 0;
        p += 8;
        n -= 8;
    }
    while (n--)
    {
        *p++ = 0;
    }

    // Handle leftover bytes
    addr += (size & ~3u);
    for (uint32_t i = 0; i < (size & 3u); i++)
        MEM(addr + i) = 0;
}

void handler_info()
{
    printf("System Information:\r\n");
    printf(" System: " SYSTEM_NAME "\r\n");
    printf(" SRAM: 0x%08lX to 0x%08lX (%ld KB)\r\n", (uint32_t)__sram_start, (uint32_t)(__sram_start + (uint32_t)__sram_length), (uint32_t)__sram_length / 1024);
    printf(" DRAM: 0x%08lX to 0x%08lX (%ld KB)\r\n", (uint32_t)__dram_start, (uint32_t)(__dram_start + (uint32_t)__dram_length), (uint32_t)__dram_length / 1024);
}

void command_not_found(char *command_name)
{
    console_puts("Command not found: ");
    console_puts(command_name);
}

uint8_t readline(char *buffer)
{
    uint8_t count = 0;
    uint8_t in = console_getc();

    while (in != '\n' && in != '\r')
    {
        // Character is printable ASCII
        if (in >= 0x20 && in < 0x7F)
        {
            console_putc(in);

            buffer[count] = in;
            count++;
        }
        // Backspace
        else if (in == 0x08 || in == 0x7F)
        {
            if (count > 0)
            {
                console_puts("\e[1D"); // Move cursor to the left
                console_putc(' ');     // Clear last character
                console_puts("\e[1D"); // Move cursor to the left again
                count--;             // Move input buffer index back
            }
        }

        in = console_getc();
    }

    buffer[count] = 0;

    return count;
}

void memtest8(uint8_t *start, uint32_t size, uint8_t target)
{
    printf("8-bit Mem Test: %lX to %lX w/ val %02X\r\n", (uint32_t)start, (uint32_t)(start + size), target);

    for (uint8_t *i = start; i < (uint8_t *)(start + size); i++)
    {
        *i = target;
    }

    for (uint8_t *i = start; i < (uint8_t *)(start + size); i++)
    {
        if (*i != target)
        {
            printf("Error at 0x%lX, expected 0x%02X, got 0x%02X\r\n", (uint32_t)i, target, *i);
        }
    }

    printf("\r\n");
}

void memtest16(uint16_t *start, uint32_t size, uint16_t target)
{
    printf("16-bit Mem Test: %lX to %lX w/ val %04X\r\n", (uint32_t)start, (uint32_t)(start + size / 2), target);

    for (uint16_t *i = start; i < (uint16_t *)(start + size / 2); i++)
    {
        *i = target;
    }

    for (uint16_t *i = start; i < (uint16_t *)(start + size / 2); i++)
    {
        if (*i != target)
        {
            printf("Error at 0x%lX, expected 0x%04X, got 0x%04X\r\n", (uint32_t)i, target, *i);
        }
    }

    printf("\r\n");
}

// Write the 32-bit address value to the same address in RAM
void memtest32(uint32_t *start, uint32_t size)
{
    printf("32-bit Mem Test: %lX to %lX\r\n", (uint32_t)start, (uint32_t)start + (uint32_t)size);

    printf("Writing...\r\n");
    for (uint32_t *i = start; i < (uint32_t *)(start + size / 4); i++)
    {
        *i = (uint32_t)i;

        if ((*i % 0x10000) == 0)
        {
            console_putc('.');
        }
    }

    printf("\r\nReading...\r\n");
    for (uint32_t *i = start; i < (uint32_t *)(start + size / 4); i++)
    {
        uint32_t got = *i;
        if (got != (uint32_t)i)
        {
            printf("Error at 0x%lX, expected 0x%lX, got 0x%lX\r\n", (uint32_t)i, (uint32_t)i, got);
        }

        if ((got % 0x10000) == 0)
        {
            console_putc('.');
        }
    }

    printf("\r\nTest complete\r\n");
}
