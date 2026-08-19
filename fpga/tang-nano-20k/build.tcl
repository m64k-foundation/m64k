set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

set_option -verilog_std sysv2017

add_file third_party/fx68k/fx68k.sv
add_file third_party/fx68k/fx68kAlu.sv
add_file third_party/fx68k/uaddrPla.sv
add_file rtl/legacy/mackerel-f/mackerel_f.v
add_file fpga/tang-nano-20k/pll.v

add_file rtl/legacy/mackerel-f/sdram_controller.v
add_file rtl/legacy/mackerel-f/sdram_cache.v
add_file third_party/sdram-tang-nano-20k/src/sdram.v

add_file rtl/legacy/mackerel-f/uart.v
add_file third_party/uart16550/rtl/verilog/uart_top.v
add_file third_party/uart16550/rtl/verilog/uart_wb.v
add_file third_party/uart16550/rtl/verilog/uart_regs.v
add_file third_party/uart16550/rtl/verilog/uart_receiver.v
add_file third_party/uart16550/rtl/verilog/uart_transmitter.v
add_file third_party/uart16550/rtl/verilog/uart_rfifo.v
add_file third_party/uart16550/rtl/verilog/uart_tfifo.v
add_file third_party/uart16550/rtl/verilog/raminfr.v
add_file third_party/uart16550/rtl/verilog/uart_sync_flops.v

add_file rtl/legacy/mackerel-f/spi.v
add_file third_party/tiny_spi/rtl/verilog/tiny_spi.v

add_file rtl/legacy/mackerel-f/timer.v
add_file rtl/legacy/mackerel-f/ws2812.v
add_file rtl/legacy/mackerel-f/irq_encoder.v
add_file rtl/legacy/mackerel-f/bus_watchdog.v

add_file fpga/tang-nano-20k/mackerel_f.cst
add_file fpga/tang-nano-20k/mackerel_f.sdc
add_file rtl/legacy/mackerel-f/boot_signal.v

set_option -include_path {third_party/uart16550/rtl/verilog}
set_option -top_module mackerel_f
set_option -output_base_name mackerel_f

run all
