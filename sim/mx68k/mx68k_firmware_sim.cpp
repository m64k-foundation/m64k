#include "Vmx68k_firmware_sim_top.h"
#include "verilated.h"

#include <cerrno>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>
#include <vector>

namespace {

volatile std::sig_atomic_t stop_requested = 0;

void on_signal(int) {
    stop_requested = 1;
}

uint64_t parse_u64(const char *text) {
    char *end = nullptr;
    errno = 0;
    const unsigned long long value = std::strtoull(text, &end, 0);
    if (errno != 0 || text[0] == '\0' || end == nullptr || *end != '\0') {
        std::fprintf(stderr, "mx68k-sim: invalid integer: %s\n", text);
        std::exit(2);
    }
    return value;
}

void usage(const char *program) {
    std::fprintf(stderr,
        "usage: %s --firmware FILE [options]\n"
        "  --firmware FILE    byte-per-line bootloader readmemh image\n"
        "  --image FILE       preload a flat binary into RAM and run it\n"
        "  --image-address N  RAM load/entry address (default: 0x400)\n"
        "  --rom FILE         preload a boot-ROM/XIP image into memory\n"
        "  --rom-address N    ROM load address (default: 0x380000)\n"
        "  --sd-image FILE    attach a raw SDHC image to SPI0 (read-only)\n"
        "  --sd-writable      permit CMD24/CMD25 to modify --sd-image\n"
        "  --sd-trace         print SD chip-select and command diagnostics\n"
        "  --platform NAME    target platform: mackerel-f (default) or mackerel-08\n"
        "  --time-scale N     accelerate behavioral timer time by N (default: 1)\n"
        "  --max-cycles N     stop after N simulated clocks (0 = unlimited)\n"
        "  --no-stdin         do not forward terminal input to UART RX\n"
        "  --command TEXT     send one command at the first prompt, then exit\n"
        "  --shell-command TEXT send TEXT at the first '# ' prompt, then exit\n"
        "  --expect TEXT      require TEXT in UART output before successful exit\n"
        "  --bus-trace        print accepted data-bus transactions to stderr\n"
        "  --retire-trace     print retired instruction PCs to stderr\n"
        "  --rx-trace         print host-to-UART receive handshakes\n"
        "  --trace-start-cycle N suppress bus/retire trace before cycle N\n"
        "  --exception-trace  print precise exception-entry metadata\n"
        "  --stop-on-exception stop after the first architectural exception\n"
        "  --stop-on-vector N stop after exception vector N (for diagnostics)\n"
        "  -h, --help         show this help\n\n"
        "The terminal is placed in no-echo character mode while the simulator\n"
        "runs. Press Ctrl-C to stop and restore the terminal.\n",
        program);
}

class TerminalGuard {
public:
    explicit TerminalGuard(bool enable) : enabled_(enable) {
        if (!enabled_)
            return;

        old_flags_ = fcntl(STDIN_FILENO, F_GETFL, 0);
        if (old_flags_ >= 0)
            fcntl(STDIN_FILENO, F_SETFL, old_flags_ | O_NONBLOCK);

        if (isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &old_term_) == 0) {
            termios raw = old_term_;
            raw.c_lflag &= static_cast<tcflag_t>(~(ICANON | ECHO));
            raw.c_cc[VMIN] = 0;
            raw.c_cc[VTIME] = 0;
            term_changed_ = (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0);
        }
    }

    TerminalGuard(const TerminalGuard &) = delete;
    TerminalGuard &operator=(const TerminalGuard &) = delete;

    ~TerminalGuard() {
        if (term_changed_)
            tcsetattr(STDIN_FILENO, TCSANOW, &old_term_);
        if (enabled_ && old_flags_ >= 0)
            fcntl(STDIN_FILENO, F_SETFL, old_flags_);
    }

private:
    bool enabled_ = false;
    int old_flags_ = -1;
    termios old_term_{};
    bool term_changed_ = false;
};

} // namespace

int main(int argc, char **argv) {
    std::string firmware;
    std::string image;
    std::string rom;
    std::string sd_image;
    std::string platform = "mackerel-f";
    uint64_t image_address = 0x400;
    uint64_t rom_address = 0x380000;
    uint64_t time_scale = 1;
    uint64_t max_cycles = 0;
    bool use_stdin = true;
    bool bus_trace = false;
    bool retire_trace = false;
    bool rx_trace = false;
    bool sd_trace = false;
    bool sd_writable = false;
    uint64_t trace_start_cycle = 0;
    bool exception_trace = false;
    bool stop_on_exception = false;
    int stop_on_vector = -1;
    std::string scripted_command;
    std::string shell_command;
    std::string expected_output;

    for (int index = 1; index < argc; ++index) {
        const std::string argument(argv[index]);
        if (argument == "-h" || argument == "--help") {
            usage(argv[0]);
            return 0;
        }
        if (argument == "--firmware" && index + 1 < argc) {
            firmware = argv[++index];
        } else if (argument == "--image" && index + 1 < argc) {
            image = argv[++index];
        } else if (argument == "--image-address" && index + 1 < argc) {
            image_address = parse_u64(argv[++index]);
        } else if (argument == "--rom" && index + 1 < argc) {
            rom = argv[++index];
        } else if (argument == "--rom-address" && index + 1 < argc) {
            rom_address = parse_u64(argv[++index]);
        } else if (argument == "--sd-image" && index + 1 < argc) {
            sd_image = argv[++index];
        } else if (argument == "--platform" && index + 1 < argc) {
            platform = argv[++index];
        } else if (argument == "--time-scale" && index + 1 < argc) {
            time_scale = parse_u64(argv[++index]);
        } else if (argument == "--max-cycles" && index + 1 < argc) {
            max_cycles = parse_u64(argv[++index]);
        } else if (argument == "--no-stdin") {
            use_stdin = false;
        } else if (argument == "--command" && index + 1 < argc) {
            scripted_command = argv[++index];
        } else if (argument == "--shell-command" && index + 1 < argc) {
            shell_command = argv[++index];
        } else if (argument == "--expect" && index + 1 < argc) {
            expected_output = argv[++index];
        } else if (argument == "--bus-trace") {
            bus_trace = true;
        } else if (argument == "--retire-trace") {
            retire_trace = true;
        } else if (argument == "--rx-trace") {
            rx_trace = true;
        } else if (argument == "--sd-trace") {
            sd_trace = true;
        } else if (argument == "--sd-writable") {
            sd_writable = true;
        } else if (argument == "--trace-start-cycle" && index + 1 < argc) {
            trace_start_cycle = parse_u64(argv[++index]);
        } else if (argument == "--exception-trace") {
            exception_trace = true;
        } else if (argument == "--stop-on-exception") {
            exception_trace = true;
            stop_on_exception = true;
        } else if (argument == "--stop-on-vector" && index + 1 < argc) {
            const uint64_t vector = parse_u64(argv[++index]);
            if (vector > 255) {
                std::fprintf(stderr, "mx68k-sim: exception vector must be <= 255\n");
                return 2;
            }
            exception_trace = true;
            stop_on_vector = static_cast<int>(vector);
        } else {
            std::fprintf(stderr, "mx68k-sim: unknown or incomplete option: %s\n",
                         argv[index]);
            usage(argv[0]);
            return 2;
        }
    }

    if (firmware.empty()) {
        std::fprintf(stderr, "mx68k-sim: --firmware is required\n");
        usage(argv[0]);
        return 2;
    }
    if (platform != "mackerel-f" && platform != "mackerel-08") {
        std::fprintf(stderr,
                     "mx68k-sim: --platform must be mackerel-f or mackerel-08\n");
        return 2;
    }
    if (time_scale == 0 || time_scale > 378000) {
        std::fprintf(stderr,
                     "mx68k-sim: --time-scale must be between 1 and 378000\n");
        return 2;
    }
    if (!rom.empty() && platform != "mackerel-08") {
        std::fprintf(stderr,
                     "mx68k-sim: --rom currently belongs to the mackerel-08 platform\n");
        return 2;
    }
    if (!sd_image.empty() && platform != "mackerel-f") {
        std::fprintf(stderr,
                     "mx68k-sim: --sd-image is supported by the mackerel-f platform\n");
        return 2;
    }
    if (access(firmware.c_str(), R_OK) != 0) {
        std::perror(firmware.c_str());
        return 2;
    }
    if (!image.empty()) {
        struct stat image_stat {};
        if (stat(image.c_str(), &image_stat) != 0) {
            std::perror(image.c_str());
            return 2;
        }
        constexpr uint64_t populated_ram = 8 * 1024 * 1024;
        if (image_address >= populated_ram || image_stat.st_size <= 0 ||
            static_cast<uint64_t>(image_stat.st_size) > populated_ram - image_address) {
            std::fprintf(stderr,
                         "mx68k-sim: image does not fit populated RAM at 0x%llx\n",
                         static_cast<unsigned long long>(image_address));
            return 2;
        }
        if (scripted_command.empty())
        {
            char run_command[32];
            std::snprintf(run_command, sizeof(run_command), "run %llx",
                          static_cast<unsigned long long>(image_address));
            scripted_command = run_command;
        }
    }
    if (!rom.empty()) {
        struct stat rom_stat {};
        if (stat(rom.c_str(), &rom_stat) != 0) {
            std::perror(rom.c_str());
            return 2;
        }
        constexpr uint64_t populated_memory = 8 * 1024 * 1024;
        if (rom_address >= populated_memory || rom_stat.st_size <= 0 ||
            static_cast<uint64_t>(rom_stat.st_size) >
                populated_memory - rom_address) {
            std::fprintf(stderr,
                         "mx68k-sim: ROM does not fit populated memory at 0x%llx\n",
                         static_cast<unsigned long long>(rom_address));
            return 2;
        }
    }
    if (!sd_image.empty()) {
        struct stat sd_stat {};
        if (stat(sd_image.c_str(), &sd_stat) != 0) {
            std::perror(sd_image.c_str());
            return 2;
        }
        if (sd_stat.st_size < 512 || (sd_stat.st_size % 512) != 0) {
            std::fprintf(stderr,
                         "mx68k-sim: SD image size must be a nonzero multiple of 512 bytes\n");
            return 2;
        }
    }
    if (sd_writable && sd_image.empty()) {
        std::fprintf(stderr,
                     "mx68k-sim: --sd-writable requires --sd-image\n");
        return 2;
    }

    std::vector<std::string> simulator_arguments;
    simulator_arguments.emplace_back(argv[0]);
    simulator_arguments.emplace_back("+FIRMWARE_HEX=" + firmware);
    if (platform == "mackerel-08")
        simulator_arguments.emplace_back("+M08_COMPAT");
    if (!image.empty()) {
        simulator_arguments.emplace_back("+IMAGE_BIN=" + image);
        simulator_arguments.emplace_back("+IMAGE_ADDR=" +
                                         std::to_string(image_address));
    }
    if (!rom.empty()) {
        simulator_arguments.emplace_back("+ROM_BIN=" + rom);
        simulator_arguments.emplace_back("+ROM_ADDR=" +
                                         std::to_string(rom_address));
    }
    if (!sd_image.empty())
        simulator_arguments.emplace_back("+SD_IMAGE=" + sd_image);
    if (sd_trace)
        simulator_arguments.emplace_back("+SD_TRACE");
    if (sd_writable)
        simulator_arguments.emplace_back("+SD_WRITABLE");
    std::vector<char *> simulator_argv;
    for (std::string &argument : simulator_arguments)
        simulator_argv.push_back(argument.data());
    Verilated::commandArgs(static_cast<int>(simulator_argv.size()),
                           simulator_argv.data());

    TerminalGuard terminal(use_stdin);
    std::signal(SIGINT, on_signal);
    std::signal(SIGTERM, on_signal);

    auto *top = new Vmx68k_firmware_sim_top;
    std::deque<uint8_t> input;
    std::string uart_output;
    uint64_t cycles = 0;
    bool line_start = true;
    bool prompt_marker = false;
    bool shell_prompt_marker = false;
    bool command_sent = false;
    bool command_completed = false;
    bool shell_command_sent = false;
    bool shell_command_completed = false;
    bool exception_seen = false;
    bool selected_exception_seen = false;
    bool previous_rx_ready = false;
    bool time_scale_activated = false;
    const std::string time_scale_marker = "Waiting for SD card...";

    top->clk = 0;
    top->rst_n = 0;
    top->timer_time_scale = 1;
    top->uart_rx_valid = 0;
    top->uart_rx_data = 0;
    top->eval();

    while (!Verilated::gotFinish() && !stop_requested && !command_completed &&
           !shell_command_completed &&
           !(stop_on_exception && exception_seen) &&
           !selected_exception_seen &&
           !top->faulted &&
           !(top->stopped && image.empty() && shell_command.empty()) &&
           (max_cycles == 0 || cycles < max_cycles)) {
        const bool rising_edge = (top->clk == 0);

        if (rising_edge && use_stdin) {
            uint8_t bytes[256];
            const ssize_t count = read(STDIN_FILENO, bytes, sizeof(bytes));
            if (count > 0) {
                for (ssize_t index = 0; index < count; ++index)
                    input.push_back(bytes[index]);
                if (rx_trace)
                    std::fprintf(stderr,
                        "[rx %10llu] queued %zd host byte(s)\n",
                        static_cast<unsigned long long>(cycles), count);
            }
        }

        top->uart_rx_valid = 0;
        if (rising_edge && top->rst_n && !input.empty() &&
            top->uart_rx_ready) {
            top->uart_rx_data = input.front();
            if (rx_trace)
                std::fprintf(stderr,
                    "[rx %10llu] accepted %02x at pc=%08x\n",
                    static_cast<unsigned long long>(cycles), input.front(),
                    top->debug_pc);
            input.pop_front();
            top->uart_rx_valid = 1;
        }

        top->clk = !top->clk;
        top->eval();
        Verilated::timeInc(1);

        if (rising_edge) {
            ++cycles;
            if (cycles == 8)
                top->rst_n = 1;

            if (top->uart_tx_valid) {
                const uint8_t byte = top->uart_tx_data;
                std::putchar(byte);
                std::fflush(stdout);
                if (!expected_output.empty() || time_scale > 1)
                    uart_output.push_back(static_cast<char>(byte));

                if (time_scale > 1 && !time_scale_activated &&
                    uart_output.size() >= time_scale_marker.size() &&
                    uart_output.compare(uart_output.size() -
                                            time_scale_marker.size(),
                                        time_scale_marker.size(),
                                        time_scale_marker) == 0) {
                    top->timer_time_scale = static_cast<uint32_t>(time_scale);
                    time_scale_activated = true;
                    std::fprintf(stderr,
                        "\n[mx68k-sim] accelerating peripheral time by %llu after SD wait began\n",
                        static_cast<unsigned long long>(time_scale));
                }

                if (prompt_marker && byte == ' ') {
                    if (!scripted_command.empty() && !command_sent) {
                        for (const char character : scripted_command)
                            input.push_back(static_cast<uint8_t>(character));
                        input.push_back('\r');
                        command_sent = true;
                    } else if (command_sent) {
                        command_completed = true;
                    }
                }
                if (shell_prompt_marker && byte == ' ') {
                    if (!shell_command.empty() && !shell_command_sent) {
                        for (const char character : shell_command)
                            input.push_back(static_cast<uint8_t>(character));
                        input.push_back('\r');
                        shell_command_sent = true;
                    } else if (shell_command_sent) {
                        shell_command_completed = true;
                    }
                }
                prompt_marker = line_start && byte == '>';
                shell_prompt_marker = line_start && byte == '#';
                line_start = byte == '\r' || byte == '\n';
            }
            if (bus_trace && cycles >= trace_start_cycle &&
                top->data_bus_valid) {
                std::fprintf(stderr, "[bus %10llu] %c %08x\n",
                    static_cast<unsigned long long>(cycles),
                    top->data_bus_command == 1 ? 'W' : 'R',
                    top->data_bus_address);
            }
            if (retire_trace && cycles >= trace_start_cycle &&
                top->retire_valid) {
                std::fprintf(stderr, "[retire %10llu] pc=%08x id=%u next=%08x D0=%08x D1=%08x D2=%08x D7=%08x A0=%08x A1=%08x A2=%08x A3=%08x A4=%08x A5=%08x A6=%08x A7=%08x\n",
                    static_cast<unsigned long long>(cycles), top->retire_pc,
                    static_cast<unsigned>(top->retire_instruction_id),
                    top->debug_pc, top->debug_d0, top->debug_d1,
                    top->debug_d2, top->debug_d7, top->debug_a0,
                    top->debug_a1, top->debug_a2, top->debug_a3,
                    top->debug_a4, top->debug_a5, top->debug_a6,
                    top->debug_a7);
            }
            if (top->exception_event_valid) {
                exception_seen = true;
                if (exception_trace && cycles >= trace_start_cycle) {
                    std::fprintf(stderr,
                        "[exception %10llu] vector=%u opcode=%04x pc=%08x address=%08x handler=%08x sp=%08x sr=%04x\n",
                        static_cast<unsigned long long>(cycles),
                        static_cast<unsigned>(top->exception_event_vector),
                        top->exception_event_opcode, top->exception_event_pc,
                        top->exception_event_address, top->debug_pc,
                        top->debug_ssp, top->debug_sr);
                }
                selected_exception_seen =
                    stop_on_vector >= 0 &&
                    top->exception_event_vector == stop_on_vector;
            }
            if (rx_trace && top->uart_rx_ready != previous_rx_ready) {
                std::fprintf(stderr, "[rx %10llu] ready=%u pc=%08x\n",
                    static_cast<unsigned long long>(cycles),
                    static_cast<unsigned>(top->uart_rx_ready),
                    top->debug_pc);
                previous_rx_ready = top->uart_rx_ready;
            }
        }
    }

    const bool faulted = top->faulted;
    const bool stopped = top->stopped;
    const uint32_t pc = top->debug_pc;
    const uint8_t fault_vector = top->fault_vector;
    const uint16_t fault_opcode = top->fault_opcode;
    const uint32_t fault_address = top->fault_address;
    const uint32_t debug_d0 = top->debug_d0;
    const uint32_t debug_d1 = top->debug_d1;
    const uint32_t debug_d2 = top->debug_d2;
    const uint32_t debug_d7 = top->debug_d7;
    top->final();
    delete top;

    std::fprintf(stderr,
                 "\n[mx68k-sim] %llu cycles, PC=%08x D0=%08x D1=%08x D2=%08x D7=%08x",
                 static_cast<unsigned long long>(cycles), pc, debug_d0,
                 debug_d1, debug_d2, debug_d7);
    if (stop_requested)
        std::fprintf(stderr, " (interrupted)\n");
    else if (faulted)
        std::fprintf(stderr, " fault vector=%u opcode=%04x address=%08x\n",
                     static_cast<unsigned>(fault_vector), fault_opcode,
                     fault_address);
    else if (stopped && image.empty())
        std::fprintf(stderr, " (CPU stopped)\n");
    else if (max_cycles != 0 && cycles >= max_cycles)
        std::fprintf(stderr, " (cycle limit)\n");
    else if (command_completed)
        std::fprintf(stderr, " (scripted command completed)\n");
    else if (shell_command_completed)
        std::fprintf(stderr, " (shell command completed)\n");
    else if (stop_on_exception && exception_seen)
        std::fprintf(stderr, " (exception stop)\n");
    else if (selected_exception_seen)
        std::fprintf(stderr, " (vector %d stop)\n", stop_on_vector);
    else
        std::fprintf(stderr, "\n");

    if (!expected_output.empty() &&
        uart_output.find(expected_output) == std::string::npos) {
        std::fprintf(stderr, "mx68k-sim: expected UART text not seen: %s\n",
                     expected_output.c_str());
        return 1;
    }
    if (image.empty() && !scripted_command.empty() && shell_command.empty() &&
        !command_completed) {
        std::fprintf(stderr, "mx68k-sim: scripted command did not complete\n");
        return 1;
    }
    if (!shell_command.empty() && !shell_command_completed) {
        std::fprintf(stderr, "mx68k-sim: shell command did not complete\n");
        return 1;
    }
    return faulted ? 1 : 0;
}
