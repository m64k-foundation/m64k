#include "Vmackerel_f_sim.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <string>
#include <termios.h>
#include <unistd.h>
#include <vector>

static volatile std::sig_atomic_t stop_requested = 0;
static void on_signal(int) { stop_requested = 1; }

static uint64_t parse_u64(const char *s) {
    char *end = nullptr;
    const unsigned long long value = std::strtoull(s, &end, 0);
    if (!s[0] || (end && *end)) {
        std::fprintf(stderr, "invalid integer: %s\n", s);
        std::exit(2);
    }
    return value;
}

static void usage(const char *argv0) {
    std::fprintf(stderr,
        "usage: %s [options] [image.bin]\n"
        "  --rom FILE          boot ROM in readmemh word format\n"
        "  --direct            reset directly into image.bin at 0x400\n"
        "  --hex-image FILE    direct-boot a byte-per-line readmemh test image\n"
        "  --max-cycles N      stop after N master-clock cycles (0 = unlimited)\n"
        "  --bus-trace         print one line per 68000 bus transaction\n"
        "  --trace[=FILE]      write a VCD (default mackerel-f.vcd)\n"
        "  --expect TEXT       fail unless UART output contains TEXT\n"
        "  --skip-sd-wait      remove waits for the intentionally absent SD card\n"
        "  --no-stdin          do not feed terminal input to the simulated UART\n",
        argv0);
}

int main(int argc, char **argv) {
    std::string image;
    std::string rom;
    std::string trace_file;
    std::string expected;
    uint64_t max_cycles = 0;
    bool direct = false;
    bool hex_image = false;
    bool bus_trace = false;
    bool use_stdin = true;
    bool skip_sd_wait = false;

    for (int i = 1; i < argc; ++i) {
        const std::string arg(argv[i]);
        if (arg == "--help" || arg == "-h") {
            usage(argv[0]);
            return 0;
        } else if (arg == "--direct") {
            direct = true;
        } else if (arg == "--hex-image" && i + 1 < argc) {
            image = argv[++i];
            hex_image = true;
            direct = true;
        } else if (arg == "--bus-trace") {
            bus_trace = true;
        } else if (arg == "--no-stdin") {
            use_stdin = false;
        } else if (arg == "--skip-sd-wait") {
            skip_sd_wait = true;
        } else if (arg == "--rom" && i + 1 < argc) {
            rom = argv[++i];
        } else if (arg == "--max-cycles" && i + 1 < argc) {
            max_cycles = parse_u64(argv[++i]);
        } else if (arg == "--expect" && i + 1 < argc) {
            expected = argv[++i];
        } else if (arg == "--trace") {
            trace_file = "mackerel-f.vcd";
        } else if (arg.rfind("--trace=", 0) == 0) {
            trace_file = arg.substr(8);
        } else if (!arg.empty() && arg[0] != '-' && image.empty()) {
            image = arg;
            direct = true;
        } else {
            std::fprintf(stderr, "unknown argument: %s\n", argv[i]);
            usage(argv[0]);
            return 2;
        }
    }

    if (direct && image.empty()) {
        std::fprintf(stderr, "--direct requires image.bin\n");
        return 2;
    }
    if (!image.empty() && access(image.c_str(), R_OK) != 0) {
        std::perror(image.c_str());
        return 2;
    }
    if (!rom.empty() && access(rom.c_str(), R_OK) != 0) {
        std::perror(rom.c_str());
        return 2;
    }

    std::vector<std::string> sim_args;
    sim_args.emplace_back(argv[0]);
    if (!image.empty())
        sim_args.emplace_back(std::string(hex_image ? "+IMAGE_HEX=" : "+IMAGE=") + image);
    if (!rom.empty()) sim_args.emplace_back("+ROM=" + rom);
    if (direct) sim_args.emplace_back("+DIRECT_BOOT");
    if (skip_sd_wait) sim_args.emplace_back("+SKIP_SD_WAIT");
    std::vector<char *> sim_argv;
    for (auto &arg : sim_args) sim_argv.push_back(arg.data());
    Verilated::commandArgs(static_cast<int>(sim_argv.size()), sim_argv.data());
    Verilated::traceEverOn(!trace_file.empty());

    auto *top = new Vmackerel_f_sim;
    VerilatedVcdC *trace = nullptr;
    if (!trace_file.empty()) {
        trace = new VerilatedVcdC;
        top->trace(trace, 99);
        trace->open(trace_file.c_str());
    }

    const int old_flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    termios old_term{};
    bool term_changed = false;
    if (use_stdin) {
        fcntl(STDIN_FILENO, F_SETFL, old_flags | O_NONBLOCK);
        if (isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &old_term) == 0) {
            termios raw = old_term;
            raw.c_lflag &= static_cast<tcflag_t>(~(ICANON | ECHO));
            raw.c_cc[VMIN] = 0;
            raw.c_cc[VTIME] = 0;
            term_changed = (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0);
        }
    }

    std::signal(SIGINT, on_signal);
    std::signal(SIGTERM, on_signal);
    std::deque<uint8_t> input;
    std::string uart_output;
    uint64_t ticks = 0;
    uint64_t cycles = 0;
    bool bus_active = false;

    top->clk = 0;
    top->reset = 1;
    top->uart_rx_valid = 0;
    top->uart_rx_data = 0;

    while (!Verilated::gotFinish() && !stop_requested &&
           (max_cycles == 0 || cycles < max_cycles)) {
        const bool rising = (top->clk == 0);
        top->clk = !top->clk;
        if (rising && cycles == 32) top->reset = 0;

        if (rising && use_stdin) {
            uint8_t buf[256];
            const ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
            if (n > 0)
                for (ssize_t i = 0; i < n; ++i) input.push_back(buf[i]);
        }

        top->uart_rx_valid = 0;
        if (rising && !input.empty() && top->uart_rx_ready) {
            top->uart_rx_data = input.front();
            input.pop_front();
            top->uart_rx_valid = 1;
        }

        top->eval();
        if (trace) trace->dump(ticks);

        if (rising) {
            ++cycles;
            if (top->uart_tx_valid) {
                std::putchar(top->uart_tx_data);
                std::fflush(stdout);
                if (!expected.empty()) uart_output.push_back(top->uart_tx_data);
            }
            const bool data_strobe = !top->debug_uds_n || !top->debug_lds_n;
            const bool iack = (top->debug_fc == 7);
            if (bus_trace && !top->debug_as_n && (data_strobe || iack) &&
                !bus_active) {
                std::fprintf(stderr,
                    "[bus %10llu] %06x %c uds=%d lds=%d fc=%x in=%04x out=%04x\n",
                    static_cast<unsigned long long>(cycles), top->debug_addr,
                    top->debug_rw_n ? 'R' : 'W', top->debug_uds_n,
                    top->debug_lds_n, top->debug_fc, top->debug_data_in,
                    top->debug_data_out);
                bus_active = true;
            }
            if (top->debug_as_n) bus_active = false;
        }
        ++ticks;
    }

    top->final();
    if (trace) {
        trace->close();
        delete trace;
    }
    delete top;
    if (term_changed) tcsetattr(STDIN_FILENO, TCSANOW, &old_term);
    if (use_stdin && old_flags >= 0) fcntl(STDIN_FILENO, F_SETFL, old_flags);
    std::fprintf(stderr, "\n[sim] stopped after %llu master-clock cycles%s\n",
                 static_cast<unsigned long long>(cycles),
                 stop_requested ? " (signal)" : "");
    if (!expected.empty() && uart_output.find(expected) == std::string::npos) {
        std::fprintf(stderr, "[sim] expected UART text not seen: %s\n",
                     expected.c_str());
        return 1;
    }
    return 0;
}
