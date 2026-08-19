// File-backed SDHC card for the Verilator Mackerel-F platform model.
//
// This is a transaction-level SPI slave: one transfer_valid pulse represents
// one completed eight-bit tiny_spi transfer.  Command framing, R1/R2/R3/R7
// responses, data tokens and CRC16 remain software-visible.  Physical SCLK
// edges and transfer latency are intentionally omitted from the fast model.
//
// The implemented subset follows the SD Physical Layer Simplified
// Specification SPI-mode command contract used by Linux mmc_spi and by the
// Mackerel-F ROM: CMD0, CMD6, CMD8, CMD9, CMD10, CMD12, CMD13, CMD16, CMD17,
// CMD18, CMD23-CMD25, CMD55, CMD58, CMD59, ACMD13, ACMD41 and ACMD51.  The
// backing file is read-only unless +SD_WRITABLE is explicitly supplied.
module mx68k_sd_spi_model (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       selected,
    input  logic       transfer_valid,
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic       card_present
);
    string image_path;
    integer image_fd;
    integer io_result;
    longint image_bytes;
    longint capacity_bytes;
    longint capacity_units;

    logic idle_state;
    logic application_command;
    logic multiple_read;
    logic [31:0] multiple_lba;
    logic write_enabled;
    logic write_pending;
    logic multiple_write;
    logic awaiting_write_token;
    logic [31:0] write_lba;
    integer write_byte_count;
    integer write_crc_count;
    logic [7:0] command_bytes [0:5];
    integer command_count;
    logic [7:0] block_buffer [0:511];
    logic [7:0] response_queue[$];
    logic selected_q;
    logic trace_enabled;
    logic [5:0] response_command;

    function automatic logic [15:0] crc16_byte(
        input logic [15:0] crc_in,
        input logic [7:0] value
    );
        logic [15:0] crc;
        begin
            crc = crc_in;
            for (int bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                if (crc[15] ^ value[bit_index])
                    crc = {crc[14:0], 1'b0} ^ 16'h1021;
                else
                    crc = {crc[14:0], 1'b0};
            end
            return crc;
        end
    endfunction

    task automatic queue_byte(input logic [7:0] value);
        response_queue.push_back(value);
    endtask

    task automatic queue_r1(input logic [7:0] value);
        begin
            // N_CR may be one through eight bytes.  One idle byte exercises
            // the host's response scan without adding unnecessary latency.
            queue_byte(8'hff);
            queue_byte(value);
        end
    endtask

    task automatic queue_register_block(
        input integer kind,
        input integer length
    );
        logic [7:0] value;
        logic [15:0] crc;
        logic [21:0] c_size;
        begin
            crc = 16'd0;
            c_size = capacity_units - 1;
            queue_byte(8'hff);
            queue_byte(8'hfe);
            for (int index = 0; index < length; index = index + 1) begin
                value = 8'h00;
                case (kind)
                    // SDHC CSD v2.0.  READ_BL_LEN is 512 bytes and C_SIZE
                    // describes the rounded-up image capacity in 512 KiB
                    // units, as required for a high-capacity card.
                    0: begin
                        case (index)
                            0: value = 8'h40;
                            1: value = 8'h0e;
                            3: value = 8'h32;
                            4: value = 8'h5b;
                            5: value = 8'h59;
                            7: value = {2'b00, c_size[21:16]};
                            8: value = c_size[15:8];
                            9: value = c_size[7:0];
                            10: value = 8'h7f;
                            11: value = 8'h80;
                            12: value = 8'h0a;
                            13: value = 8'h40;
                            15: value = 8'h01;
                            default: value = 8'h00;
                        endcase
                    end
                    // Stable simulated CID: manufacturer 0x4d, OEM "MX",
                    // product "MX68K", revision 1.0 and serial 1.
                    1: begin
                        case (index)
                            0: value = 8'h4d;
                            1: value = "M";
                            2: value = "X";
                            3: value = "M";
                            4: value = "X";
                            5: value = "6";
                            6: value = "8";
                            7: value = "K";
                            8: value = 8'h10;
                            12: value = 8'h01;
                            13: value = 8'h01;
                            14: value = 8'h81;
                            15: value = 8'h01;
                            default: value = 8'h00;
                        endcase
                    end
                    // SCR: structure v1, SD Physical Specification 2.0,
                    // security v2 and one-/four-bit native bus widths.
                    2: begin
                        case (index)
                            0: value = 8'h02;
                            1: value = 8'h05;
                            default: value = 8'h00;
                        endcase
                    end
                    // SD status and CMD6 switch-function status.  Leaving
                    // optional performance fields zero keeps default speed.
                    default: value = 8'h00;
                endcase
                queue_byte(value);
                crc = crc16_byte(crc, value);
            end
            queue_byte(crc[15:8]);
            queue_byte(crc[7:0]);
        end
    endtask

    task automatic queue_image_block(input logic [31:0] lba);
        logic [15:0] crc;
        longint byte_offset;
        begin
            byte_offset = longint'(lba) * 512;
            if ((byte_offset < 0) || (byte_offset + 512 > image_bytes)) begin
                // A host must not request blocks beyond the CSD capacity.  The
                // file is the authoritative populated portion of this model.
                queue_byte(8'h08);
            end else begin
                io_result = $fseek(image_fd, byte_offset, 0);
                if (io_result != 0)
                    $fatal(1, "SD image seek failed at LBA %0d", lba);
                io_result = $fread(block_buffer, image_fd, 0, 512);
                if (io_result != 512)
                    $fatal(1, "SD image short read at LBA %0d: %0d bytes",
                           lba, io_result);
                crc = 16'd0;
                queue_byte(8'hff);
                queue_byte(8'hfe);
                for (int index = 0; index < 512; index = index + 1) begin
                    queue_byte(block_buffer[index]);
                    crc = crc16_byte(crc, block_buffer[index]);
                end
                queue_byte(crc[15:8]);
                queue_byte(crc[7:0]);
            end
        end
    endtask

    task automatic commit_image_block(input logic [31:0] lba);
        longint byte_offset;
        begin
            byte_offset = longint'(lba) * 512;
            if (!write_enabled || byte_offset < 0 ||
                byte_offset + 512 > image_bytes) begin
                // Data response token: write error.
                queue_byte(8'h0d);
            end else begin
                io_result = $fseek(image_fd, byte_offset, 0);
                if (io_result != 0)
                    $fatal(1, "SD image seek failed while writing LBA %0d", lba);
                for (int index = 0; index < 512; index = index + 1)
                    $fwrite(image_fd, "%c", block_buffer[index]);
                $fflush(image_fd);
                // Accepted data-response, one busy byte, then ready.  Linux's
                // mmc_spi_writeblock() consumes this exact sequence.
                queue_byte(8'h05);
                queue_byte(8'h00);
                queue_byte(8'hff);
            end
        end
    endtask

    task automatic execute_command;
        logic [5:0] command;
        logic [31:0] argument;
        logic [7:0] r1;
        logic was_application_command;
        begin
            command = command_bytes[0][5:0];
            response_command = command;
            argument = {command_bytes[1], command_bytes[2],
                        command_bytes[3], command_bytes[4]};
            r1 = idle_state ? 8'h01 : 8'h00;
            was_application_command = application_command;
            application_command = 1'b0;
            if (trace_enabled)
                $display("[mx68k-sd] CMD%0d arg=%08x app=%0d idle=%0d",
                         command, argument, was_application_command, idle_state);

            if (!card_present) begin
                // An unpopulated MISO line remains high.
            end else if (was_application_command && command == 6'd41) begin
                idle_state = 1'b0;
                queue_r1(8'h00);
            end else if (was_application_command && command == 6'd51) begin
                queue_r1(r1);
                if (!idle_state)
                    queue_register_block(2, 8);
            end else if (was_application_command && command == 6'd13) begin
                queue_r1(r1);
                if (!idle_state)
                    queue_register_block(3, 64);
            end else begin
                case (command)
                    6'd0: begin
                        idle_state = 1'b1;
                        multiple_read = 1'b0;
                        queue_r1(8'h01);
                    end
                    6'd6: begin
                        queue_r1(r1);
                        if (!idle_state)
                            queue_register_block(4, 64);
                    end
                    6'd8: begin
                        queue_r1(r1);
                        queue_byte(8'h00);
                        queue_byte(8'h00);
                        queue_byte(8'h01);
                        queue_byte(8'haa);
                    end
                    6'd9: begin
                        queue_r1(r1);
                        if (!idle_state)
                            queue_register_block(0, 16);
                    end
                    6'd10: begin
                        queue_r1(r1);
                        if (!idle_state)
                            queue_register_block(1, 16);
                    end
                    6'd12: begin
                        multiple_read = 1'b0;
                        queue_r1(r1);
                    end
                    6'd13: begin
                        queue_r1(r1);
                        queue_byte(8'h00);
                    end
                    6'd16: queue_r1(argument == 32'd512 ? r1 :
                                                              (r1 | 8'h40));
                    6'd17: begin
                        if (idle_state)
                            queue_r1(r1);
                        else if ((longint'(argument) * 512) + 512 > image_bytes)
                            queue_r1(8'h20);
                        else begin
                            queue_r1(8'h00);
                            queue_image_block(argument);
                        end
                    end
                    6'd18: begin
                        if (idle_state)
                            queue_r1(r1);
                        else if ((longint'(argument) * 512) + 512 > image_bytes)
                            queue_r1(8'h20);
                        else begin
                            multiple_lba = argument;
                            multiple_read = 1'b1;
                            queue_r1(8'h00);
                        end
                    end
                    6'd23: queue_r1(r1);
                    6'd24, 6'd25: begin
                        if (idle_state)
                            queue_r1(r1);
                        else if (!write_enabled)
                            queue_r1(r1 | 8'h04);
                        else if ((longint'(argument) * 512) + 512 > image_bytes)
                            queue_r1(r1 | 8'h20);
                        else begin
                            write_lba = argument;
                            write_pending = 1'b1;
                            multiple_write = command == 6'd25;
                            awaiting_write_token = 1'b1;
                            write_byte_count = 0;
                            write_crc_count = 0;
                            queue_r1(r1);
                        end
                    end
                    6'd55: begin
                        application_command = 1'b1;
                        queue_r1(r1);
                    end
                    6'd58: begin
                        queue_r1(r1);
                        // Busy/ready, CCS (block addressing), and the common
                        // 2.7-3.6 V operating window.
                        queue_byte(idle_state ? 8'h40 : 8'hc0);
                        queue_byte(8'hff);
                        queue_byte(8'h80);
                        queue_byte(8'h00);
                    end
                    6'd59: queue_r1(r1);
                    default: queue_r1(r1 | 8'h04);
                endcase
            end
        end
    endtask

    initial begin
        image_fd = 0;
        image_bytes = 0;
        capacity_bytes = 0;
        capacity_units = 0;
        card_present = 1'b0;
        trace_enabled = $test$plusargs("SD_TRACE");
        write_enabled = $test$plusargs("SD_WRITABLE");
        if ($value$plusargs("SD_IMAGE=%s", image_path)) begin
            image_fd = $fopen(image_path, write_enabled ? "r+b" : "rb");
            if (image_fd == 0)
                $fatal(1, "cannot open SD_IMAGE=%s", image_path);
            io_result = $fseek(image_fd, 0, 2);
            if (io_result != 0)
                $fatal(1, "cannot seek SD_IMAGE=%s", image_path);
            image_bytes = $ftell(image_fd);
            io_result = $fseek(image_fd, 0, 0);
            if (image_bytes < 512 || (image_bytes % 512) != 0)
                $fatal(1, "SD_IMAGE size must be a nonzero multiple of 512: %0d",
                       image_bytes);
            capacity_units = (image_bytes + 524287) / 524288;
            capacity_bytes = capacity_units * 524288;
            if (capacity_units > 4_194_304)
                $fatal(1, "SD_IMAGE exceeds the SDHC/SDXC CSD v2 limit");
            card_present = 1'b1;
            if (write_enabled)
                $display("[mx68k-sim] attached writable SDHC image %s (%0d bytes, CSD capacity %0d bytes)",
                         image_path, image_bytes, capacity_bytes);
            else
                $display("[mx68k-sim] attached read-only SDHC image %s (%0d bytes, CSD capacity %0d bytes)",
                         image_path, image_bytes, capacity_bytes);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_data = 8'hff;
            idle_state = 1'b1;
            application_command = 1'b0;
            multiple_read = 1'b0;
            multiple_lba = 32'd0;
            write_pending = 1'b0;
            multiple_write = 1'b0;
            awaiting_write_token = 1'b0;
            write_lba = 32'd0;
            write_byte_count = 0;
            write_crc_count = 0;
            command_count = 0;
            selected_q = 1'b0;
            response_command = 6'd0;
            response_queue.delete();
        end else if (!selected) begin
            rx_data = 8'hff;
            // CS high tri-states MISO and abandons partial command framing,
            // but it does not replace CMD12 or the FD stop token.  Linux's
            // mmc_spi stack may split command and data phases across SPI
            // messages, so multiblock/read-write state must survive here.
            command_count = 0;
            response_queue.delete();
        end else if (transfer_valid) begin
            rx_data = 8'hff;
            if (response_queue.size() != 0) begin
                rx_data = response_queue.pop_front();
                if (trace_enabled &&
                    (response_command inside {6'd5, 6'd8, 6'd12, 6'd41,
                                               6'd58}))
                    $display("[mx68k-sd] CMD%0d RX=%02x remaining=%0d",
                             response_command, rx_data,
                             response_queue.size());
            end else if (command_count != 0) begin
                command_bytes[command_count] = tx_data;
                if (command_count == 5) begin
                    command_count = 0;
                    execute_command();
                end else begin
                    command_count = command_count + 1;
                end
            end else if (write_pending && awaiting_write_token) begin
                if (multiple_write && tx_data == 8'hfd) begin
                    write_pending = 1'b0;
                    multiple_write = 1'b0;
                    awaiting_write_token = 1'b0;
                    queue_byte(8'hff);
                end else if ((!multiple_write && tx_data == 8'hfe) ||
                             (multiple_write && tx_data == 8'hfc)) begin
                    awaiting_write_token = 1'b0;
                    write_byte_count = 0;
                    write_crc_count = 0;
                end
            end else if (write_pending && write_byte_count < 512) begin
                block_buffer[write_byte_count] = tx_data;
                write_byte_count = write_byte_count + 1;
            end else if (write_pending && write_crc_count < 2) begin
                write_crc_count = write_crc_count + 1;
                if (write_crc_count == 2) begin
                    commit_image_block(write_lba);
                    if (multiple_write) begin
                        write_lba = write_lba + 1'b1;
                        awaiting_write_token = 1'b1;
                        write_byte_count = 0;
                        write_crc_count = 0;
                    end else begin
                        write_pending = 1'b0;
                    end
                end
            end else if (tx_data[7:6] == 2'b01) begin
                command_bytes[0] = tx_data;
                command_count = 1;
            end else if (multiple_read) begin
                if ((longint'(multiple_lba) * 512) + 512 <= image_bytes) begin
                    queue_image_block(multiple_lba);
                    multiple_lba = multiple_lba + 1'b1;
                    rx_data = response_queue.pop_front();
                end else begin
                    multiple_read = 1'b0;
                    rx_data = 8'h08;
                end
            end
        end
        if (rst_n && selected != selected_q) begin
            if (trace_enabled)
                $display("[mx68k-sd] chip select %s",
                         selected ? "asserted" : "released");
            selected_q = selected;
        end
    end
endmodule
