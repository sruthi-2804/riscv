`timescale 1ns / 1ps
// Phase 9 directed suite: full ALU register/immediate coverage at CPU level,
// forwarding-priority proof, x0 forwarding exclusion, and consecutive taken
// branches. Program is loaded hierarchically - no project file is modified.
//
// Expected results are computed by hand from the RV32I spec and encoded in
// the checks; the bench prints PASS/FAIL per architectural register.
//
// Phase 9 closure additions:
//  - case 1: a finite counted loop built on a BACKWARD conditional branch,
//    which is the only place in the suite that exercises a negative B-type
//    immediate and repeated taken-branch flushes on the same instruction
//  - case 4: a cycle-level monitor proving a genuine load-use dependency
//    stalls for EXACTLY one cycle - it fails on a 0-cycle stall (missed
//    hazard) and on a 2+-cycle stall (over-stall), not just on a wrong
//    final architectural result

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
        // Jump over the unreachable poison at [34] into the closure block.
        dut.imem_inst.memory[33] = 32'h01C0006F;  // JAL x0, +28       -> [40]
        dut.imem_inst.memory[34] = 32'h03700E13;  // ADDI x28, x0, 55  poison (unreachable)

        // ----------------------------------------------------------------
        // Case 1: finite counted loop on a BACKWARD conditional branch.
        // The loop body runs 5 times; the branch at [46] is TAKEN 4 times
        // (negative B-type immediate, -8) and falls through on the 5th.
        // [47] sits in the taken branch's shadow: it must be fetched and
        // flushed on each of the 4 taken iterations and execute exactly
        // once, on the fall-through. x11 = 1 proves that; x11 = 5 would
        // mean wrong-path instructions were allowed to retire.
        // ----------------------------------------------------------------
        dut.imem_inst.memory[40] = 32'h00000593;  // ADDI x11, x0, 0   shadow counter = 0
        dut.imem_inst.memory[41] = 32'h00000E93;  // ADDI x29, x0, 0   i   = 0
        dut.imem_inst.memory[42] = 32'h00000F13;  // ADDI x30, x0, 0   acc = 0
        dut.imem_inst.memory[43] = 32'h00500F93;  // ADDI x31, x0, 5   limit = 5
        dut.imem_inst.memory[44] = 32'h001E8E93;  // loop: ADDI x29, x29, 1
        dut.imem_inst.memory[45] = 32'h003F0F13;  //       ADDI x30, x30, 3
        dut.imem_inst.memory[46] = 32'hFFFE9CE3;  //       BNE  x29, x31, -8  -> [44]
        dut.imem_inst.memory[47] = 32'h00158593;  // ADDI x11, x11, 1  loop-exit / branch shadow

        // ----------------------------------------------------------------
        // Case 4: the suite's only load-use dependency. [50] consumes the
        // result of the load at [49] immediately, so exactly one one-cycle
        // stall must occur in this whole program. dmem[0] is written first
        // so the loaded value is non-zero and the result is meaningful.
        // ----------------------------------------------------------------
        dut.imem_inst.memory[48] = 32'h01E02023;  // SW   x30, 0(x0)   dmem[0] = 15
        dut.imem_inst.memory[49] = 32'h00002F83;  // LW   x31, 0(x0)   x31 = 15
        dut.imem_inst.memory[50] = 32'h007F8F93;  // ADDI x31, x31, 7  load-use -> 22
        dut.imem_inst.memory[51] = 32'h0000006F;  // JAL x0, 0         park
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

    // ------------------------------------------------------------------
    // Case 4: load-use stall duration monitor.
    //
    // load_use_hazard is combinational in cycle N; its architectural
    // effect (PC freeze, IF/ID freeze, ID/EX bubble) lands in the pipeline
    // registers at N+1, and the pipeline must be moving again at N+2.
    // The freeze checks are therefore deferred one edge and the resume
    // check two, mirroring the |=> form used by the bound SVA.
    //
    // A 0-cycle stall is caught by stall_events staying at 0; a 2+-cycle
    // stall is caught twice over, by bad_run_errors (run length != 1) and
    // by resume_errors (ID/EX still bubbled when it should be moving).
    // ------------------------------------------------------------------
    int stall_events       = 0;   // number of contiguous load_use_hazard runs
    int stall_run_len      = 0;   // length of the run currently in progress
    int bad_run_errors     = 0;   // runs whose length was not exactly 1
    int pc_freeze_errors   = 0;
    int ifid_freeze_errors = 0;
    int idex_bubble_errors = 0;
    int resume_errors      = 0;

    logic [31:0] pc_at_stall;
    logic [31:0] ifid_at_stall;
    logic        ifidv_at_stall;
    bit          freeze_due = 1'b0;
    bit          resume_due = 1'b0;

    always @(posedge clk) begin
        if (reset) begin
            stall_run_len = 0;
            freeze_due    = 1'b0;
            resume_due    = 1'b0;
        end
        else begin
            // N+2: the stalled instruction must now be moving through EX.
            if (resume_due) begin
                if (dut.id_ex_valid !== 1'b1) begin
                    resume_errors++;
                    $display("FAIL @%0t: pipeline did not resume the cycle after a load-use stall", $time);
                end
                resume_due = 1'b0;
            end

            // N+1: PC and IF/ID frozen, ID/EX bubbled.
            if (freeze_due) begin
                if (dut.pc_value !== pc_at_stall) begin
                    pc_freeze_errors++;
                    $display("FAIL @%0t: PC advanced during load-use stall (%h -> %h)",
                             $time, pc_at_stall, dut.pc_value);
                end
                if (dut.if_id_instruction !== ifid_at_stall ||
                    dut.if_id_valid       !== ifidv_at_stall) begin
                    ifid_freeze_errors++;
                    $display("FAIL @%0t: IF/ID changed during load-use stall", $time);
                end
                if (dut.id_ex_valid !== 1'b0) begin
                    idex_bubble_errors++;
                    $display("FAIL @%0t: ID/EX not bubbled during load-use stall", $time);
                end
                freeze_due = 1'b0;
                resume_due = 1'b1;
            end

            // Run-length accounting on the hazard sampled at this edge.
            if (dut.load_use_hazard === 1'b1) begin
                stall_run_len++;
                if (stall_run_len == 1) begin
                    pc_at_stall    = dut.pc_value;
                    ifid_at_stall  = dut.if_id_instruction;
                    ifidv_at_stall = dut.if_id_valid;
                    freeze_due     = 1'b1;
                end
            end
            else if (stall_run_len != 0) begin
                stall_events++;
                if (stall_run_len != 1) begin
                    bad_run_errors++;
                    $display("FAIL @%0t: load-use stall lasted %0d cycles, expected exactly 1",
                             $time, stall_run_len);
                end
                stall_run_len = 0;
            end
        end
    end

    task automatic check_count(input int actual, input int expected, input string why);
        checks++;
        if (actual !== expected) begin
            errors++;
            $display("FAIL: %s (got %0d, expected %0d)", why, actual, expected);
        end
        else $display("PASS: %s (%0d)", why, actual);
    endtask

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

        #2000;

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

        $display("==== case 1: backward conditional branch / counted loop ====");

        check_reg(29, 32'd5,  "loop ran exactly 5 iterations (backward BNE, negative B-immediate)");
        check_reg(30, 32'd15, "loop accumulator 5 x 3 proves the body executed 5 times");
        check_reg(11, 32'd1,  "branch shadow retired once, not 5x (wrong path suppressed)");

        $display("==== case 4: load-use stall is exactly one cycle ====");

        check_reg(31, 32'd22, "load-use consumer got the loaded value (15 + 7)");
        check_count(stall_events,       1, "load-use stall events in this program");
        check_count(bad_run_errors,     0, "stalls whose duration was not exactly 1 cycle");
        check_count(pc_freeze_errors,   0, "PC-freeze violations during the stall cycle");
        check_count(ifid_freeze_errors, 0, "IF/ID-freeze violations during the stall cycle");
        check_count(idex_bubble_errors, 0, "ID/EX-bubble violations during the stall cycle");
        check_count(resume_errors,      0, "failures to resume the cycle after the stall");

        $display("==== alu/hazard suite result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_ALU_HAZARD_TB: ALL PASS");
        else             $display("CPU_ALU_HAZARD_TB: FAILED");
        $finish;
    end

endmodule
