`timescale 1ns / 1ps
// Unit-level self-checking testbench for data_memory byte_enable behavior.
// Verifies that only enabled byte lanes are written and all others preserved.

module tb_data_memory_subword_check;

    logic        clk;
    logic        reset;
    logic        mem_read;
    logic        mem_write;
    logic [31:0] address;
    logic [31:0] write_data;
    logic [31:0] read_data;
    logic [3:0]  byte_enable;

    int errors = 0;
    int checks = 0;

    data_memory dut (
        .clk         (clk),
        .reset       (reset),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .address     (address),
        .write_data  (write_data),
        .read_data   (read_data),
        .byte_enable (byte_enable)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic do_write(input logic [31:0] addr,
                            input logic [31:0] data,
                            input logic [3:0]  be);
        @(negedge clk);
        address     = addr;
        write_data  = data;
        byte_enable = be;
        mem_write   = 1'b1;
        @(negedge clk);
        mem_write   = 1'b0;
    endtask

    task automatic expect_word(input int idx,
                               input logic [31:0] expected,
                               input string why);
        checks++;
        mem_read = 1'b1;
        address  = idx * 4;
        #1;
        if (read_data !== expected) begin
            errors++;
            $display("FAIL: word[%0d] = %h, expected %h  (%s)", idx, read_data, expected, why);
        end
        else begin
            $display("PASS: word[%0d] = %h  (%s)", idx, expected, why);
        end
        mem_read = 1'b0;
    endtask

    initial begin
        reset = 1'b1;
        mem_read = 1'b0; mem_write = 1'b0;
        address = '0; write_data = '0; byte_enable = '0;
        #22;
        reset = 1'b0;

        // Full-word write, then single-byte writes into each lane
        do_write(32'd0, 32'hFFFFFFFF, 4'b1111);
        expect_word(0, 32'hFFFFFFFF, "SW-style full-word write");

        do_write(32'd0, 32'h000000AA, 4'b0001);
        expect_word(0, 32'hFFFFFFAA, "SB lane 0: other 3 bytes preserved");

        do_write(32'd0, 32'h0000BB00, 4'b0010);
        expect_word(0, 32'hFFFFBBAA, "SB lane 1: other 3 bytes preserved");

        do_write(32'd0, 32'h00CC0000, 4'b0100);
        expect_word(0, 32'hFFCCBBAA, "SB lane 2: other 3 bytes preserved");

        do_write(32'd0, 32'hDD000000, 4'b1000);
        expect_word(0, 32'hDDCCBBAA, "SB lane 3: other 3 bytes preserved");

        // Halfword lanes
        do_write(32'd4, 32'h11223344, 4'b1111);
        do_write(32'd4, 32'h0000ABCD, 4'b0011);
        expect_word(1, 32'h1122ABCD, "SH lower half: upper half preserved");

        do_write(32'd4, 32'hEF010000, 4'b1100);
        expect_word(1, 32'hEF01ABCD, "SH upper half: lower half preserved");

        // No lanes enabled -> no write at all
        do_write(32'd8, 32'hDEADBEEF, 4'b0000);
        expect_word(2, 32'h00000000, "byte_enable=0000 writes nothing");

        // mem_read low -> read_data forced to zero
        checks++;
        mem_read = 1'b0; address = 32'd0; #1;
        if (read_data !== 32'b0) begin
            errors++;
            $display("FAIL: read_data = %h with mem_read=0, expected 0", read_data);
        end
        else $display("PASS: read_data forced to 0 when mem_read=0");

        $display("==== data_memory subword result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("DMEM_SUBWORD_TB: ALL PASS");
        else             $display("DMEM_SUBWORD_TB: FAILED");
        $finish;
    end

endmodule
