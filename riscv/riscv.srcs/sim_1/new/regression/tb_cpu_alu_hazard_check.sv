`timescale 1ns / 1ps
// Phase 9 directed suite: full ALU register/immediate coverage at CPU level,
// forwarding-priority proof, x0 forwarding exclusion, and consecutive taken
// branches. Program is loaded hierarchically - no project file is modified.
//
// Expected results are computed by hand from the RV32I spec and encoded in
// the checks; the bench prints PASS/FAIL per architectural register.

module tb_cpu_alu_hazard_check;

    logic clk;
    logic reset;

    int errors = 0;
    int checks = 0;
    int inv_errors = 0;

    riscv_cpu dut (
        .clk   (clk),
        .reset (reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        #1;
        for (int i = 0; i < 256; i++)
            dut.imem_inst.memory[i] = 32'h00000013;           // NOP

        // Operand setup: one positive, one negative value
        dut.imem_inst.memory[0]  = 32'h06400093;  // ADDI x1, x0, 100
        dut.imem_inst.memory[1]  = 32'hFF900113;  // ADDI x2, x0, -7   (0xFFFFFFF9)

        // R-type arithmetic/logical.
        // i2 consumes x2 at distance 1 (EX/MEM fwd) and x1 at distance 2
        // (MEM/WB fwd); i3 consumes x1 at distance 3 (regfile WB bypass).
        dut.imem_inst.memory[2]  = 32'h002081B3;  // ADD x3, x1, x2  -> 93
        dut.imem_inst.memory[3]  = 32'h40208233;  // SUB x4, x1, x2  -> 107
        dut.imem_inst.memory[4]  = 32'h0020F2B3;  // AND x5, x1, x2  -> 0x60
        dut.imem_inst.memory[5]  = 32'h0020E333;  // OR  x6, x1, x2  -> 0xFFFFFFFD
        dut.imem_inst.memory[6]  = 32'h0020C3B3;  // XOR x7, x1, x2  -> 0xFFFFFF9D

        // I-type logical
        dut.imem_inst.memory[7]  = 32'h0FF17413;  // ANDI x8,  x2, 0xFF -> 0xF9
        dut.imem_inst.memory[8]  = 32'h7030E493;  // ORI  x9,  x1, 0x703 -> 0x767
        dut.imem_inst.memory[9]  = 32'hFFF14513;  // XORI x10, x2, -1  -> ~x2 = 6

        // Shifts, register and immediate, on a negative value
        dut.imem_inst.memory[10] = 32'h00300593;  // ADDI x11, x0, 3
        dut.imem_inst.memory[11] = 32'h00B11633;  // SLL  x12, x2, x11 -> 0xFFFFFFC8
        dut.imem_inst.memory[12] = 32'h00B156B3;  // SRL  x13, x2, x11 -> 0x1FFFFFFF
        dut.imem_inst.memory[13] = 32'h40B15733;  // SRA  x14, x2, x11 -> 0xFFFFFFFF
        dut.imem_inst.memory[14] = 32'h00409793;  // SLLI x15, x1, 4   -> 0x640
        dut.imem_inst.memory[15] = 32'h01C15813;  // SRLI x16, x2, 28  -> 0xF
        dut.imem_inst.memory[16] = 32'h41C15893;  // SRAI x17, x2, 28  -> 0xFFFFFFFF

        // Comparisons: signed vs unsigned disagree on x2
        dut.imem_inst.memory[17] = 32'h00112933;  // SLT  x18, x2, x1  -> 1
        dut.imem_inst.memory[18] = 32'h0020A9B3;  // SLT  x19, x1, x2  -> 0
        dut.imem_inst.memory[19] = 32'h00113A33;  // SLTU x20, x2, x1  -> 0
        dut.imem_inst.memory[20] = 32'h0020BAB3;  // SLTU x21, x1, x2  -> 1
        dut.imem_inst.memory[21] = 32'hFFA12B13;  // SLTI  x22, x2, -6 -> 1
        dut.imem_inst.memory[22] = 32'h0650BB93;  // SLTIU x23, x1, 101 -> 1

        // EX/MEM priority: two in-flight writes to x24; the consumer must
        // take the newer EX/MEM value (33), not the MEM/WB value (11).
        dut.imem_inst.memory[23] = 32'h00B00C13;  // ADDI x24, x0, 11
        dut.imem_inst.memory[24] = 32'h016C0C13;  // ADDI x24, x24, 22 -> 33
        dut.imem_inst.memory[25] = 32'h000C0CB3;  // ADD  x25, x24, x0 -> 33

        // x0 forwarding exclusion: an in-flight "write" to x0 must not be
        // forwarded to a consumer of x0.
        dut.imem_inst.memory[26] = 32'h04D00013;  // ADDI x0, x0, 77
        dut.imem_inst.memory[27] = 32'h00000D33;  // ADD  x26, x0, x0  -> 0

        // Consecutive taken branches; the first branch's shadow contains
        // another branch that must be flushed, not followed.
        dut.imem_inst.memory[28] = 32'h00000463;  // BEQ x0, x0, +8    taken -> [30]
        dut.imem_inst.memory[29] = 32'h00000A63;  // BEQ x0, x0, +20   shadow: if executed -> poison [34]
        dut.imem_inst.memory[30] = 32'h00000463;  // BEQ x0, x0, +8    taken -> [32]
        dut.imem_inst.memory[31] = 32'h06300E13;  // ADDI x28, x0, 99  shadow marker - must flush
        dut.imem_inst.memory[32] = 32'h00100D93;  // ADDI x27, x0, 1   good path
        dut.imem_inst.memory[33] = 32'h0000006F;  // JAL x0, 0         park
        dut.imem_inst.memory[34] = 32'h03700E13;  // ADDI x28, x0, 55  poison (unreachable)
    end

    // Valid/bubble invariants, checked every cycle
    always @(posedge clk) begin
        if (!reset) begin
            if ($isunknown(dut.control_flush)) begin
                inv_errors++;
                $display("INVARIANT FAIL @%0t: control_flush is X", $time);
            end
            if (dut.id_ex_valid === 1'b0 &&
                (dut.id_ex_reg_write !== 1'b0 || dut.id_ex_mem_write !== 1'b0 ||
                 dut.id_ex_branch !== 1'b0 || dut.id_ex_jal !== 1'b0 || dut.id_ex_jalr !== 1'b0)) begin
                inv_errors++;
                $display("INVARIANT FAIL @%0t: bubble carries live control signals", $time);
            end
        end
    end

    task automatic check_reg(input int idx, input logic [31:0] expected, input string why);
        checks++;
        if (dut.regfile_inst.registers[idx] !== expected) begin
            errors++;
            $display("FAIL: x%0d = %h, expected %h  (%s)",
                     idx, dut.regfile_inst.registers[idx], expected, why);
        end
        else $display("PASS: x%0d = %h  (%s)", idx, expected, why);
    endtask

    initial begin
        reset = 1'b1;
        #12;
        reset = 1'b0;

        #1000;

        $display("==== ALU / forwarding-priority / consecutive-branch checks ====");

        check_reg(1,  32'd100,      "ADDI positive");
        check_reg(2,  32'hFFFFFFF9, "ADDI negative sign-extends");
        check_reg(3,  32'd93,       "ADD with EX/MEM + MEM/WB forwarded operands");
        check_reg(4,  32'd107,      "SUB with distance-3 regfile-bypass operand");
        check_reg(5,  32'h00000060, "AND");
        check_reg(6,  32'hFFFFFFFD, "OR");
        check_reg(7,  32'hFFFFFF9D, "XOR");
        check_reg(8,  32'h000000F9, "ANDI");
        check_reg(9,  32'h00000767, "ORI");
        check_reg(10, 32'd6,        "XORI with -1 (bitwise NOT)");
        check_reg(12, 32'hFFFFFFC8, "SLL by register amount");
        check_reg(13, 32'h1FFFFFFF, "SRL is logical (zero fill)");
        check_reg(14, 32'hFFFFFFFF, "SRA is arithmetic (sign fill)");
        check_reg(15, 32'h00000640, "SLLI");
        check_reg(16, 32'h0000000F, "SRLI by 28");
        check_reg(17, 32'hFFFFFFFF, "SRAI by 28");
        check_reg(18, 32'd1,        "SLT signed: -7 < 100");
        check_reg(19, 32'd0,        "SLT signed: 100 < -7 is false");
        check_reg(20, 32'd0,        "SLTU unsigned: 0xFFFFFFF9 < 100 is false");
        check_reg(21, 32'd1,        "SLTU unsigned: 100 < 0xFFFFFFF9");
        check_reg(22, 32'd1,        "SLTI signed: -7 < -6");
        check_reg(23, 32'd1,        "SLTIU: 100 < 101");
        check_reg(24, 32'd33,       "back-to-back writes to same rd");
        check_reg(25, 32'd33,       "EX/MEM priority beats MEM/WB (33, not 11)");
        check_reg(26, 32'd0,        "x0 excluded from forwarding (not 77+77)");
        check_reg(27, 32'd1,        "target after two consecutive taken branches");
        check_reg(28, 32'd0,        "both branch shadows flushed (no 99, no 55)");

        checks++;
        if (inv_errors != 0) begin
            errors++;
            $display("FAIL: %0d valid/bubble invariant violations", inv_errors);
        end
        else $display("PASS: bubbles carry no live controls; control_flush never X");

        $display("==== alu/hazard suite result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_ALU_HAZARD_TB: ALL PASS");
        else             $display("CPU_ALU_HAZARD_TB: FAILED");
        $finish;
    end

endmodule
