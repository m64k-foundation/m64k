module m64k_shifter_tb;
    import m64k_arch_pkg::*;
    import m64k_shift_reference_pkg::*;

    logic [31:0] operand;
    m64k_operand_size_t size;
    logic [5:0] count;
    logic direction_left;
    logic [1:0] shift_kind;
    logic old_extend;
    m64k_alu_result_t actual;

    m64k_shifter dut (.*,.shift_result(actual));

    function automatic logic [31:0] boundary_operand(input integer index);
        case (index)
            0:  return 32'h0000_0000;
            1:  return 32'hffff_ffff;
            2:  return 32'h0000_0001;
            3:  return 32'h8000_0000;
            4:  return 32'h7fff_ffff;
            5:  return 32'h5555_5555;
            6:  return 32'haaaa_aaaa;
            7:  return 32'h0000_0080;
            8:  return 32'h0000_007f;
            9:  return 32'h0000_00ff;
            10: return 32'h0000_8000;
            11: return 32'h0000_7fff;
            12: return 32'h0000_ffff;
            13: return 32'h8000_0001;
            14: return 32'h0101_0101;
            default: return 32'hdead_beef;
        endcase
    endfunction

    task automatic check_one;
        m64k_alu_result_t expected;
        begin
            #1;
            expected = reference_shift(operand, size, count,
                                       direction_left, shift_kind,
                                       old_extend);
            assert (actual === expected)
                else $fatal(1,
                    "shifter mismatch op=%08x size=%0d count=%0d left=%0d kind=%0d x=%0d actual=%h expected=%h",
                    operand, size, count, direction_left, shift_kind,
                    old_extend, actual, expected);
        end
    endtask

    initial begin
        operand = '0;
        size = M64K_OP_BYTE;
        count = '0;
        direction_left = 1'b0;
        shift_kind = 2'b00;
        old_extend = 1'b0;

        // Exhaust all control/count combinations over sign, carry and
        // alternating-bit boundary operands for every architectural width.
        for (int operand_index = 0; operand_index < 16; operand_index++) begin
            for (int size_index = 0; size_index < 3; size_index++) begin
                for (int kind_index = 0; kind_index < 4; kind_index++) begin
                    for (int left_index = 0; left_index < 2; left_index++) begin
                        for (int x_index = 0; x_index < 2; x_index++) begin
                            for (int count_index = 0;
                                 count_index < 64; count_index++) begin
                                operand = boundary_operand(operand_index);
                                size = m64k_operand_size_t'(size_index);
                                shift_kind = kind_index[1:0];
                                direction_left = left_index[0];
                                old_extend = x_index[0];
                                count = count_index[5:0];
                                check_one();
                            end
                        end
                    end
                end
            end
        end

        $display("PASS: barrel shifter matches documented iterative M00 model (49152 cases)");
        $finish;
    end
endmodule
