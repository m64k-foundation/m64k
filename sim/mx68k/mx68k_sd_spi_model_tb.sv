module mx68k_sd_spi_model_tb;
    logic clk;
    logic rst_n;
    logic selected;
    logic transfer_valid;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic card_present;

    mx68k_sd_spi_model model (.*);

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic transfer(
        input logic [7:0] tx_value,
        output logic [7:0] rx_value
    );
        begin
            @(negedge clk);
            tx_data = tx_value;
            transfer_valid = 1'b1;
            @(posedge clk);
            #1 rx_value = rx_data;
            @(negedge clk);
            transfer_valid = 1'b0;
        end
    endtask

    task automatic send_command(
        input logic [5:0] command,
        input logic [31:0] argument,
        input logic [7:0] crc
    );
        logic [7:0] ignored;
        begin
            transfer(8'h40 | command, ignored);
            transfer(argument[31:24], ignored);
            transfer(argument[23:16], ignored);
            transfer(argument[15:8], ignored);
            transfer(argument[7:0], ignored);
            transfer(crc, ignored);
        end
    endtask

    task automatic read_response(output logic [7:0] response);
        begin
            response = 8'hff;
            for (int attempt = 0;
                 attempt < 8 && response[7]; attempt = attempt + 1)
                transfer(8'hff, response);
            assert (!response[7])
                else $fatal(1, "SD response timeout");
        end
    endtask

    task automatic wait_data_token;
        logic [7:0] value;
        begin
            value = 8'hff;
            for (int attempt = 0;
                 attempt < 8 && value == 8'hff; attempt = attempt + 1)
                transfer(8'hff, value);
            assert (value == 8'hfe)
                else $fatal(1, "SD data token mismatch: %02x", value);
        end
    endtask

    logic [7:0] value;
    logic [7:0] register_data [0:15];
    initial begin
        rst_n = 1'b0;
        selected = 1'b0;
        transfer_valid = 1'b0;
        tx_data = 8'hff;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        assert (card_present)
            else $fatal(1, "test requires +SD_IMAGE");

        selected = 1'b1;
        repeat (10) transfer(8'hff, value);

        send_command(0, 32'd0, 8'h95);
        read_response(value);
        assert (value == 8'h01);

        send_command(8, 32'h0000_01aa, 8'h87);
        read_response(value);
        assert (value == 8'h01);
        transfer(8'hff, value); assert (value == 8'h00);
        transfer(8'hff, value); assert (value == 8'h00);

        transfer(8'hff, value); assert (value == 8'h01);
        transfer(8'hff, value); assert (value == 8'haa);

        send_command(55, 32'd0, 8'h01);
        read_response(value);
        assert (value == 8'h01);
        // Linux mmc_spi may release chip select between CMD55 and its ACMD.
        // CMD55's application-command latch belongs to card state and must
        // survive that transaction boundary.
        selected = 1'b0;
        @(negedge clk);
        selected = 1'b1;
        send_command(41, 32'h4000_0000, 8'h01);
        read_response(value);
        assert (value == 8'h00);

        send_command(58, 32'd0, 8'h01);
        read_response(value);
        assert (value == 8'h00);
        transfer(8'hff, value); assert (value == 8'hc0);
        transfer(8'hff, value); assert (value == 8'hff);
        transfer(8'hff, value); assert (value == 8'h80);
        transfer(8'hff, value); assert (value == 8'h00);

        send_command(9, 32'd0, 8'h01);
        read_response(value);
        assert (value == 8'h00);
        wait_data_token();
        for (int index = 0; index < 16; index = index + 1)
            transfer(8'hff, register_data[index]);
        assert (register_data[0][7:6] == 2'b01);
        assert (register_data[5][3:0] == 4'd9);
        transfer(8'hff, value);
        transfer(8'hff, value);

        // The generated fixture is sparse/zero-filled.  Validate all 512
        // payload bytes plus their CRC16, not merely successful command init.
        send_command(17, 32'd0, 8'h01);
        read_response(value);
        assert (value == 8'h00);
        wait_data_token();
        for (int index = 0; index < 512; index = index + 1) begin
            transfer(8'hff, value);
            assert (value == 8'h00);
        end
        transfer(8'hff, value); assert (value == 8'h00);
        transfer(8'hff, value); assert (value == 8'h00);

        // CMD24 framing follows SD SPI mode and Linux mmc_spi_writeblock():
        // FE token, 512 payload bytes, two CRC bytes, 05 acceptance, busy,
        // then FF ready.  Read the sector back through CMD17.
        send_command(24, 32'd1, 8'h01);
        read_response(value);
        assert (value == 8'h00);
        // Command and data are separate spi_message operations in mmc_spi.
        selected = 1'b0;
        @(negedge clk);
        selected = 1'b1;
        transfer(8'hfe, value);
        for (int index = 0; index < 512; index = index + 1)
            transfer(index[7:0], value);
        transfer(8'h00, value);
        transfer(8'h00, value);
        transfer(8'hff, value); assert (value == 8'h05);
        transfer(8'hff, value); assert (value == 8'h00);
        transfer(8'hff, value); assert (value == 8'hff);

        send_command(17, 32'd1, 8'h01);
        read_response(value);
        assert (value == 8'h00);
        wait_data_token();
        for (int index = 0; index < 512; index = index + 1) begin
            transfer(8'hff, value);
            assert (value == index[7:0]);
        end
        transfer(8'hff, value);
        transfer(8'hff, value);

        // CMD18 remains active across a chip-select interval and terminates
        // only when CMD12 is received.
        send_command(18, 32'd0, 8'h01);
        read_response(value);
        assert (value == 8'h00);
        selected = 1'b0;
        @(negedge clk);
        selected = 1'b1;
        wait_data_token();
        for (int index = 0; index < 512; index = index + 1) begin
            transfer(8'hff, value);
            assert (value == 8'h00);
        end
        transfer(8'hff, value);
        transfer(8'hff, value);
        send_command(12, 32'd0, 8'h01);
        read_response(value);
        assert (value == 8'h00);

        // One MiB contains LBAs 0..2047; SDHC addressing is block based.
        send_command(17, 32'd2048, 8'h01);
        read_response(value);
        assert (value == 8'h20);

        selected = 1'b0;
        transfer(8'hff, value);
        assert (value == 8'hff);
        $display("PASS: file-backed SDHC SPI read/write model");
        $finish;
    end
endmodule
