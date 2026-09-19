`timescale 1ns / 1ps
// NEW full-CPU self-checking testbench for the directed branch program that is
// already loaded in instruction_memory.sv. Does not modify any project file.
//
// Program under test (from instruction_memory.sv):
//   x1=5, x2=3
//   BNE  x1,x2  taken      -> x20 marker (99) must be flushed
//   BNE  x1,x1  not taken  -> x21=21 executes
//   x8=-1, x9=1
//   BLT  x8,x9  taken      -> x22 flushed
//   BGE  x8,x9  not taken  -> x23=23 executes
//   BLTU x8,x9  not taken  -> x24=24 executes
//   BGEU x8,x9  taken      -> x25 flushed
//   x10=7, ADD x11=x10+x9=8 (forwarding)
//   BNE  x11,x10 taken on forwarded x11 -> x26 flushed, x27=27 executes
//   BGE  x9,x8  taken (signed, negative operand) -> x28 flushed, x29=29 executes

module tb_cpu_branch_check;

    logic clk;
    logic reset;

    int errors = 0;
    int checks = 0;

    riscv_cpu dut (
        .clk   (clk),
        .reset (reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_reg(input int idx, input logic [31:0] expected, input string why);
        checks++;
        if (dut.regfile_inst.registers[idx] !== expected) begin
            errors++;
            $display("FAIL: x%0d = %h, expected %h  (%s)",
                     idx, dut.regfile_inst.registers[idx], expected, why);
        end
        else begin
            $display("PASS: x%0d = %h  (%s)", idx, expected, why);
        end
    endtask

    initial begin
        reset = 1'b1;
        #12;
        reset = 1'b0;

        // Program is ~24 slots + stalls/flushes; 100 cycles is ample.
        #1000;

        $display("==== full-CPU branch suite checks ====");

        check_reg(1,  32'd5,         "ADDI x1,x0,5");
        check_reg(2,  32'd3,         "ADDI x2,x0,3");
        check_reg(20, 32'd0,         "BNE taken: wrong-path ADDI x20,99 flushed");
        check_reg(21, 32'd21,        "BNE not-taken: fall-through executes");
        check_reg(8,  32'hFFFFFFFF,  "ADDI x8,x0,-1");
        check_reg(9,  32'd1,         "ADDI x9,x0,1");
        check_reg(22, 32'd0,         "BLT signed taken: wrong path flushed");
        check_reg(23, 32'd23,        "BGE signed not-taken: fall-through executes");
        check_reg(24, 32'd24,        "BLTU unsigned not-taken: fall-through executes");
        check_reg(25, 32'd0,         "BGEU unsigned taken: wrong path flushed");
        check_reg(10, 32'd7,         "ADDI x10,x0,7");
        check_reg(11, 32'd8,         "ADD x11,x10,x9 via forwarding");
        check_reg(26, 32'd0,         "BNE on forwarded x11 taken: wrong path flushed");
        check_reg(27, 32'd27,        "branch target after forwarded BNE executes");
        check_reg(28, 32'd0,         "BGE signed taken w/ negative operand: flushed");
        check_reg(29, 32'd29,        "branch target after signed BGE executes");

        $display("==== cpu branch suite result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_BRANCH_TB: ALL PASS");
        else             $display("CPU_BRANCH_TB: FAILED");
        $finish;
    end

endmodule
