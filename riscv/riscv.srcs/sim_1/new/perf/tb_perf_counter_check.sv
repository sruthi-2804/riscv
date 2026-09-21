`timescale 1ns / 1ps
// Phase 10.1: self-checking validation of the four performance counters.
//
// The counters are instrumentation, so this suite proves two separate
// things about them.
//
// 1. DEFINITIONAL EQUALITY (the shadow model).
//    The testbench re-derives all four counters from the DUT's own
//    hazard/valid signals, independently, in its own always block, and
//    compares them every cycle. If the RTL ever counted something else -
//    a stall EVENT instead of a stall CYCLE, reg_write instead of
//    mem_wb_valid, a doubled flush - the shadow diverges immediately and
//    the cycle of divergence is printed.
//
// 2. ARCHITECTURAL ATTRIBUTION (the directed program).
//    Equality with a shadow model is not enough on its own: a shared
//    misconception would be reproduced by both. So the program below puts
//    every event the counters must distinguish at a KNOWN program
//    counter, and each retirement is attributed to the instruction that
//    produced it through mem_wb_pc_plus_4, which is written
//    unconditionally for every instruction (ex_pc_plus_4 = id_ex_pc + 4,
//    an unconditional assign). That yields a per-PC retirement histogram,
//    which is what actually proves a store retires, a branch retires, and
//    a wrong-path instruction does not.
//
// Nothing here drives the DUT except clk and reset; the program is loaded
// hierarchically into the existing instruction memory, exactly as the
// other suites do, so no project source file is modified.

module tb_perf_counter_check;

    logic clk;
    logic reset;

    int errors = 0;
    int checks = 0;

    riscv_cpu dut (.clk(clk), .reset(reset));

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------
    // Program layout. Byte address of word w is 4*w.
    //
    //  w0  ADDI x1, x0, 5
    //  w1  ADDI x2, x0, 5
    //  w2  SW   x1, 4(x0)      retires, writes NO register          (test 5)
    //  w3  BNE  x1, x2, +8     NOT taken (x1 == x2)                 (test 8)
    //  w4  BEQ  x1, x2, +8     TAKEN, pc 16 -> 24                   (tests 6, 9)
    //  w5  ADDI x20, x0, 99    POISON: branch shadow                (test 4)
    //  w6  LW   x3, 4(x0)      x3 = 5
    //  w7  ADDI x4, x3, 1      load-use consumer                    (tests 3, 7)
    //  w8  JAL  x5, +12        pc 32 -> 44, x5 = 36                 (test 10)
    //  w9  ADDI x21, x0, 99    POISON: JAL shadow
    //  w10 ADDI x22, x0, 99    POISON: JAL shadow
    //  w11 ADDI x6, x0, 60     JALR base
    //  w12 JALR x7, 0(x6)      pc 48 -> 60, x7 = 52                 (test 10)
    //  w13 ADDI x23, x0, 99    POISON: JALR shadow
    //  w14 ADDI x24, x0, 99    POISON: JALR shadow
    //  w15 ADDI x31, x0, 123   SENTINEL - last useful instruction
    //  w16..w19 NOP            drain pad (see below)
    //  w20 JAL  x0, 0          park
    //
    // Architecturally retiring instructions, w0..w15: 11.
    // w5, w9, w10, w13 and w14 are wrong-path and must never retire.
    //
    // DRAIN PAD. The sentinel is the retirement endpoint, but stall_count
    // and flush_count observe ID and EX, which run three and two stages
    // AHEAD of MEM/WB. So an instruction fetched after the sentinel can
    // still bump those two counters before the sentinel commits. The
    // parking JAL does exactly that: it reaches EX one cycle after the
    // sentinel and raises control_flush, which lands inside the window
    // even though its two lost cycles land outside it - the measurement
    // would report a flush that cost nothing. Four NOPs between the
    // sentinel and the park close that shadow: NOPs neither stall nor
    // flush, so nothing fetched after the endpoint can perturb the
    // measurement. Every workload in this phase uses the same pad, and
    // the flush_pc_other check below is what proves it worked.
    // ------------------------------------------------------------------
    localparam int PC_STORE     = 8;    // w2
    localparam int PC_BR_NT     = 12;   // w3
    localparam int PC_BR_TAKEN  = 16;   // w4
    localparam int PC_JAL       = 32;   // w8
    localparam int PC_JALR      = 48;   // w12
    localparam int PC_SENTINEL  = 60;   // w15

    localparam int EXP_RETIRED  = 11;
    localparam int EXP_STALLS   = 1;    // the single w6/w7 load-use pair
    localparam int EXP_FLUSHES  = 3;    // taken BEQ, JAL, JALR

    // Cycle budget for an in-order 5-stage pipeline with EX-resolved
    // control flow: 4 fill cycles, then one cycle per retired instruction,
    // plus one cycle per stall cycle, plus two discarded cycles per
    // redirect (the entries in IF/ID and ID/EX are both killed).
    localparam int EXP_CYCLES = 4 + EXP_RETIRED + EXP_STALLS + 2*EXP_FLUSHES;

    int poison_pc [5];
    initial begin
        poison_pc[0] = 20; poison_pc[1] = 36; poison_pc[2] = 40;
        poison_pc[3] = 52; poison_pc[4] = 56;
    end

    initial begin
        #1;
        for (int i = 0; i < 256; i++)
            dut.imem_inst.memory[i] = 32'h00000013;     // NOP

        dut.imem_inst.memory[0]  = 32'h00500093;  // ADDI x1, x0, 5
        dut.imem_inst.memory[1]  = 32'h00500113;  // ADDI x2, x0, 5
        dut.imem_inst.memory[2]  = 32'h00102223;  // SW   x1, 4(x0)
        dut.imem_inst.memory[3]  = 32'h00209463;  // BNE  x1, x2, +8   not taken
        dut.imem_inst.memory[4]  = 32'h00208463;  // BEQ  x1, x2, +8   taken
        dut.imem_inst.memory[5]  = 32'h06300A13;  // ADDI x20, x0, 99  POISON
        dut.imem_inst.memory[6]  = 32'h00402183;  // LW   x3, 4(x0)
        dut.imem_inst.memory[7]  = 32'h00118213;  // ADDI x4, x3, 1    load-use
        dut.imem_inst.memory[8]  = 32'h00C002EF;  // JAL  x5, +12
        dut.imem_inst.memory[9]  = 32'h06300A93;  // ADDI x21, x0, 99  POISON
        dut.imem_inst.memory[10] = 32'h06300B13;  // ADDI x22, x0, 99  POISON
        dut.imem_inst.memory[11] = 32'h03C00313;  // ADDI x6, x0, 60
        dut.imem_inst.memory[12] = 32'h000303E7;  // JALR x7, 0(x6)
        dut.imem_inst.memory[13] = 32'h06300B93;  // ADDI x23, x0, 99  POISON
        dut.imem_inst.memory[14] = 32'h06300C13;  // ADDI x24, x0, 99  POISON
        dut.imem_inst.memory[15] = 32'h07B00F93;  // ADDI x31, x0, 123 SENTINEL
        // w16..w19 stay NOP (the loop above): drain pad.
        dut.imem_inst.memory[20] = 32'h0000006F;  // JAL  x0, 0        park
    end

    // ------------------------------------------------------------------
    // Shadow model: an independent re-derivation of all four counters.
    //
    // Sampling discipline. The DUT's counter block samples mem_wb_valid /
    // load_use_hazard / control_flush as they stand JUST BEFORE a rising
    // edge. The shadow therefore latches those three at the preceding
    // falling edge, and compares the results at #1 after the rising edge,
    // which is past the non-blocking update region. Every read below is a
    // settled register output, so there is no race with the DUT.
    // ------------------------------------------------------------------
    longint sh_cycle  = 0;
    longint sh_instr  = 0;
    longint sh_stall  = 0;
    longint sh_flush  = 0;

    int shadow_mismatches = 0;
    int bubble_retire_err = 0;      // instret moved while MEM/WB held a bubble
    int first_mismatch_cy = -1;

    logic pre_mem_wb_valid;
    logic pre_load_use;
    logic pre_flush;

    longint prev_instret = 0;

    always @(negedge clk) begin
        pre_mem_wb_valid = dut.mem_wb_valid;
        pre_load_use     = dut.load_use_hazard;
        pre_flush        = dut.control_flush;
    end

    // Per-PC retirement histogram, plus event attribution.
    int  retire_hits [0:255];
    int  store_retired_no_regwrite = 0;
    int  br_nt_retired_no_regwrite = 0;
    int  br_tk_retired_no_regwrite = 0;
    int  flush_pc_brtk  = 0;
    int  flush_pc_jal   = 0;
    int  flush_pc_jalr  = 0;
    int  flush_pc_other = 0;

    // Captured at the edge on which the sentinel commits.
    bit      armed    = 1'b0;
    bit      captured = 1'b0;
    longint  cap_cycle, cap_instr, cap_stall, cap_flush;

    initial for (int i = 0; i < 256; i++) retire_hits[i] = 0;

    always @(posedge clk) begin
        #1;   // post-NBA: everything read below is a settled register output

        if (reset) begin
            sh_cycle = 0; sh_instr = 0; sh_stall = 0; sh_flush = 0;
            prev_instret = 0;
        end
        else begin
            // Advance the shadow using the values the DUT sampled.
            sh_cycle++;
            if (pre_mem_wb_valid) sh_instr++;
            if (pre_load_use)     sh_stall++;
            if (pre_flush)        sh_flush++;

            if (dut.cycle_count   !== sh_cycle ||
                dut.instret_count !== sh_instr ||
                dut.stall_count   !== sh_stall ||
                dut.flush_count   !== sh_flush) begin
                shadow_mismatches++;
                if (first_mismatch_cy < 0) begin
                    first_mismatch_cy = sh_cycle;
                    $display("FAIL @%0t cycle %0d: counters diverge from the shadow model",
                             $time, sh_cycle);
                    $display("   cycle   rtl=%0d shadow=%0d", dut.cycle_count,   sh_cycle);
                    $display("   instret rtl=%0d shadow=%0d", dut.instret_count, sh_instr);
                    $display("   stall   rtl=%0d shadow=%0d", dut.stall_count,   sh_stall);
                    $display("   flush   rtl=%0d shadow=%0d", dut.flush_count,   sh_flush);
                end
            end

            // Test 3: instret must be frozen whenever MEM/WB held a bubble.
            if (!pre_mem_wb_valid && (dut.instret_count !== prev_instret)) begin
                bubble_retire_err++;
                $display("FAIL @%0t: instret advanced on a MEM/WB bubble (%0d -> %0d)",
                         $time, prev_instret, dut.instret_count);
            end
            prev_instret = dut.instret_count;

            // Capture at the edge on which the sentinel commits. "armed" was
            // set one cycle earlier, when the sentinel occupied MEM/WB.
            if (armed && !captured) begin
                captured  = 1'b1;
                cap_cycle = dut.cycle_count;
                cap_instr = dut.instret_count;
                cap_stall = dut.stall_count;
                cap_flush = dut.flush_count;
            end

            // Retirement attribution for the instruction now in MEM/WB.
            if (dut.mem_wb_valid) begin
                int rpc;
                rpc = int'(dut.mem_wb_pc_plus_4) - 4;
                if (rpc >= 0 && rpc < 1024) retire_hits[rpc >> 2]++;

                if (rpc == PC_SENTINEL) armed = 1'b1;

                // Tests 5 and 6: these retire with mem_wb_reg_write low.
                if (rpc == PC_STORE    && !dut.mem_wb_reg_write) store_retired_no_regwrite++;
                if (rpc == PC_BR_NT    && !dut.mem_wb_reg_write) br_nt_retired_no_regwrite++;
                if (rpc == PC_BR_TAKEN && !dut.mem_wb_reg_write) br_tk_retired_no_regwrite++;
            end

            // Tests 9 and 10: attribute each flush event to the instruction
            // in EX that caused it.
            if (dut.control_flush) begin
                case (int'(dut.id_ex_pc))
                    PC_BR_TAKEN: flush_pc_brtk++;
                    PC_JAL:      flush_pc_jal++;
                    PC_JALR:     flush_pc_jalr++;
                    default:     flush_pc_other++;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    task automatic check_count(input longint actual, input longint expected, input string why);
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

    // ------------------------------------------------------------------
    initial begin
        reset = 1'b1;
        #12;

        $display("==== test 1: counters are zero under reset ====");
        check_count(dut.cycle_count,   0, "cycle_count is 0 while reset is asserted");
        check_count(dut.instret_count, 0, "instret_count is 0 while reset is asserted");
        check_count(dut.stall_count,   0, "stall_count is 0 while reset is asserted");
        check_count(dut.flush_count,   0, "flush_count is 0 while reset is asserted");

        reset = 1'b0;

        wait (captured == 1'b1);
        #1;

        $display("==== test 2: cycle_count tracks every non-reset clock edge ====");
        check_count(shadow_mismatches, 0,
            "cycles on which any counter diverged from the independent shadow model");

        $display("==== tests 3 and 4: bubbles and wrong-path entries do not retire ====");
        check_count(bubble_retire_err, 0,
            "edges on which instret_count advanced while MEM/WB held a bubble");
        for (int i = 0; i < 5; i++) begin
            checks++;
            if (retire_hits[poison_pc[i] >> 2] != 0) begin
                errors++;
                $display("FAIL: wrong-path instruction at pc %0d retired %0d time(s)",
                         poison_pc[i], retire_hits[poison_pc[i] >> 2]);
            end
            else $display("PASS: wrong-path instruction at pc %0d never retired", poison_pc[i]);
        end
        check_reg(20, 32'd0, "branch-shadow poison never wrote its register");
        check_reg(21, 32'd0, "JAL-shadow poison never wrote its register");
        check_reg(22, 32'd0, "JAL-shadow poison never wrote its register");
        check_reg(23, 32'd0, "JALR-shadow poison never wrote its register");
        check_reg(24, 32'd0, "JALR-shadow poison never wrote its register");

        $display("==== tests 5 and 6: stores and branches retire without a register write ====");
        check_count(store_retired_no_regwrite, 1,
            "SW retired exactly once with mem_wb_reg_write low");
        check_count(br_nt_retired_no_regwrite, 1,
            "not-taken branch retired exactly once with mem_wb_reg_write low");
        check_count(br_tk_retired_no_regwrite, 1,
            "taken branch retired exactly once with mem_wb_reg_write low");
        check_count(retire_hits[PC_STORE    >> 2], 1, "SW appears once in the retirement histogram");
        check_count(retire_hits[PC_BR_NT    >> 2], 1, "not-taken branch appears once in the histogram");
        check_count(retire_hits[PC_BR_TAKEN >> 2], 1, "taken branch appears once in the histogram");

        $display("==== test 7: the one-cycle load-use hazard costs exactly one stall cycle ====");
        check_count(cap_stall, EXP_STALLS,
            "stall_count over the measurement window (one LW/ADDI pair)");

        $display("==== tests 8, 9 and 10: flush accounting ====");
        check_count(cap_flush, EXP_FLUSHES,
            "flush_count over the window (taken BEQ + JAL + JALR)");
        check_count(flush_pc_brtk,  1, "flush events attributed to the taken branch at pc 16");
        check_count(flush_pc_jal,   1, "flush events attributed to the JAL at pc 32");
        check_count(flush_pc_jalr,  1, "flush events attributed to the JALR at pc 48");
        check_count(flush_pc_other, 0,
            "flush events with no attributable cause (proves the drain pad closed the sentinel's shadow)");
        checks++;
        if (flush_pc_brtk + flush_pc_jal + flush_pc_jalr != int'(cap_flush)) begin
            errors++;
            $display("FAIL: attributed flushes (%0d) != flush_count (%0d)",
                     flush_pc_brtk + flush_pc_jal + flush_pc_jalr, cap_flush);
        end
        else $display("PASS: the not-taken branch at pc 12 contributed no flush event");

        $display("==== retirement and cycle accounting over the window ====");
        check_count(cap_instr, EXP_RETIRED, "instret_count at the sentinel commit");
        check_count(cap_cycle, EXP_CYCLES,
            "cycle_count at the sentinel commit (4 fill + 11 retired + 1 stall + 3x2 flush)");

        $display("==== architectural results unchanged by instrumentation ====");
        check_reg(1,  32'd5,   "ADDI x1");
        check_reg(2,  32'd5,   "ADDI x2");
        check_reg(3,  32'd5,   "LW x3 read back the stored value");
        check_reg(4,  32'd6,   "ADDI x4 consumed the loaded value after the stall");
        check_reg(5,  32'd36,  "JAL link = pc+4 (32+4)");
        check_reg(7,  32'd52,  "JALR link = pc+4 (48+4)");
        check_reg(31, 32'd123, "sentinel executed");
        checks++;
        if (dut.dmem_inst.memory[1] !== 32'd5) begin
            errors++;
            $display("FAIL: dmem[1] = %h, expected 00000005", dut.dmem_inst.memory[1]);
        end
        else $display("PASS: dmem[1] = 00000005 (the store took effect)");

        // Test 1 again, this time from a running state.
        $display("==== test 1 (again): reset clears the counters from a running state ====");
        checks++;
        if (dut.cycle_count == 0) begin
            errors++;
            $display("FAIL: cycle_count was already 0 before the second reset - test is vacuous");
        end
        else $display("PASS: counters are non-zero before the second reset (cycle_count = %0d)",
                      dut.cycle_count);

        @(negedge clk);
        reset = 1'b1;
        @(posedge clk);
        #1;
        check_count(dut.cycle_count,   0, "cycle_count returned to 0 on reset");
        check_count(dut.instret_count, 0, "instret_count returned to 0 on reset");
        check_count(dut.stall_count,   0, "stall_count returned to 0 on reset");
        check_count(dut.flush_count,   0, "flush_count returned to 0 on reset");

        $display("==== perf counter sanity result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("PERF_COUNTER_TB: ALL PASS");
        else             $display("PERF_COUNTER_TB: FAILED");
        $finish;
    end

    // Backstop: never let the suite hang.
    initial begin
        #20000;
        $display("FAIL: timeout - the sentinel never committed (captured=%0b)", captured);
        $display("PERF_COUNTER_TB: FAILED");
        $finish;
    end

endmodule
