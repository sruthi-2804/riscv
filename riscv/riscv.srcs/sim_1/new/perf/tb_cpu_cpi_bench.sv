`timescale 1ns / 1ps
// Phase 10.2: CPI measurement workloads.
//
// These are measurement programs, not verification programs. Each one is
// built to isolate ONE source of pipeline cost so the resulting CPI is
// interpretable rather than merely small. The random generator is
// deliberately not used here: a random instruction mix produces a number
// nobody can attribute.
//
// ==================================================================
// MEASUREMENT WINDOW
// ==================================================================
// Every workload uses exactly the same window, so the six numbers are
// directly comparable.
//
//   START  the first rising clock edge on which reset is deasserted.
//          cycle_count is 0 up to and including the last edge under
//          reset, and becomes 1 on that first free-running edge.
//
//   END    the rising edge on which the SENTINEL instruction commits,
//          i.e. the edge at which it leaves MEM/WB. The testbench sees
//          the sentinel occupy MEM/WB (identified by mem_wb_pc_plus_4,
//          which carries id_ex_pc + 4 for every instruction), arms, and
//          samples all four counters at the next edge.
//
// So cycle_count at capture is exactly the number of clock edges needed
// to retire everything from the first instruction through the sentinel,
// INCLUDING the four pipeline-fill cycles, every stall cycle, every
// bubble and every wrong-path cycle. Nothing is subtracted.
//
// Two contamination hazards are handled explicitly.
//
//   PARKING INSTRUCTION. The existing suites park on JAL x0,0. A parking
//   JAL raises control_flush every iteration, forever. It cannot affect
//   cycle_count or instret_count here, because the window closes at the
//   sentinel - but control_flush is generated in EX, which runs two
//   stages AHEAD of the retirement point, so the park's first flush lands
//   INSIDE the window while its two lost cycles land outside it. The
//   measurement would then report a flush event that cost nothing.
//
//   DRAIN PAD. The fix, applied uniformly: four NOPs between the sentinel
//   and the park. NOPs neither stall nor flush, so nothing fetched after
//   the endpoint can perturb any counter before the sentinel commits.
//   Each workload asserts late_flushes == 0, which is what proves the pad
//   actually closed the shadow rather than merely being present.
//
// ==================================================================
// CYCLE MODEL
// ==================================================================
// For this in-order 5-stage pipeline with control flow resolved in EX:
//
//   cycles = 4 + retired + stall_cycles + 2 x flush_events
//
//   4              pipeline fill: the first instruction commits on edge 5
//   retired        one commit per cycle at steady state
//   stall_cycles   each load-use stall inserts one bubble
//   2 x flushes    a redirect kills the entries in IF/ID and ID/EX
//
// Each workload states its predicted counters from this model and the
// testbench compares them against hardware. A mismatch is reported as a
// failure, so the model is under test too, not just the CPU.
//
// The workloads run back to back in one simulation. Between them the DUT
// is fully reset, which clears the register file, the data memory, every
// pipeline valid bit and all four counters, so no workload can inherit
// state from its predecessor.

module tb_cpu_cpi_bench;

    logic clk;
    logic reset;

    int errors = 0;
    int checks = 0;

    riscv_cpu dut (.clk(clk), .reset(reset));

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    localparam logic [31:0] NOP = 32'h00000013;   // ADDI x0, x0, 0

    // ------------------------------------------------------------------
    // RV32I encoders
    // ------------------------------------------------------------------
    function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1,
                                          input logic [2:0] f3, input logic [4:0] rd,
                                          input logic [6:0] opc);
        return {imm, rs1, f3, rd, opc};
    endfunction

    function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2,
                                          input logic [4:0] rs1, input logic [2:0] f3);
        return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] enc_b(input logic [12:0] imm, input logic [4:0] rs2,
                                          input logic [4:0] rs1, input logic [2:0] f3);
        return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] enc_j(input logic [20:0] imm, input logic [4:0] rd);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    function automatic logic [31:0] i_addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return enc_i(imm, rs1, 3'b000, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] i_lw(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return enc_i(imm, rs1, 3'b010, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] i_sw(input logic [4:0] rs2, rs1, input logic [11:0] imm);
        return enc_s(imm, rs2, rs1, 3'b010);
    endfunction

    function automatic logic [31:0] i_beq(input logic [4:0] rs1, rs2, input logic [12:0] imm);
        return enc_b(imm, rs2, rs1, 3'b000);
    endfunction

    function automatic logic [31:0] i_bne(input logic [4:0] rs1, rs2, input logic [12:0] imm);
        return enc_b(imm, rs2, rs1, 3'b001);
    endfunction

    function automatic logic [31:0] i_jal(input logic [4:0] rd, input logic [20:0] imm);
        return enc_j(imm, rd);
    endfunction

    function automatic logic [31:0] i_jalr(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return enc_i(imm, rs1, 3'b000, rd, 7'b1100111);
    endfunction

    // ------------------------------------------------------------------
    // Measurement plumbing
    // ------------------------------------------------------------------
    int      bm_sentinel_pc = -1;
    bit      bm_active      = 1'b0;
    bit      bm_armed       = 1'b0;
    bit      bm_captured    = 1'b0;

    longint  cap_cycle, cap_instr, cap_stall, cap_flush;

    // Flush events raised by anything at or past the sentinel, i.e. by the
    // drain pad or the park. Must be zero: that is the proof that the pad
    // closed the endpoint's shadow.
    int      late_flushes   = 0;

    always @(posedge clk) begin
        #1;   // post-NBA sampling point: every read below is settled

        if (!reset && bm_active) begin

            if (dut.control_flush && (int'(dut.id_ex_pc) >= bm_sentinel_pc))
                late_flushes++;

            if (!bm_captured) begin
                // Armed one cycle ago, when the sentinel occupied MEM/WB:
                // it commits on this edge, which closes the window.
                if (bm_armed) begin
                    bm_captured = 1'b1;
                    cap_cycle   = dut.cycle_count;
                    cap_instr   = dut.instret_count;
                    cap_stall   = dut.stall_count;
                    cap_flush   = dut.flush_count;
                end

                if (dut.mem_wb_valid &&
                    ((int'(dut.mem_wb_pc_plus_4) - 4) == bm_sentinel_pc))
                    bm_armed = 1'b1;
            end
        end
    end

    // Identical startup for every workload: reset spans two rising edges
    // (the program counter, register file and data memory all reset
    // synchronously and need at least one), then deasserts half a cycle
    // before the first free-running edge.
    task automatic do_reset();
        @(negedge clk);
        reset = 1'b1;
        @(negedge clk);
        @(negedge clk);
        reset = 1'b0;
    endtask

    task automatic fill_nops();
        for (int i = 0; i < 256; i++)
            dut.imem_inst.memory[i] = NOP;
    endtask

    // Sentinel + 4-NOP drain pad + park, placed at word `w`.
    // Returns the sentinel's byte PC.
    function automatic int place_tail(input int w);
        dut.imem_inst.memory[w] = i_addi(5'd31, 5'd0, 12'd123);   // SENTINEL
        // w+1 .. w+4 stay NOP: the drain pad.
        dut.imem_inst.memory[w+5] = i_jal(5'd0, 21'd0);           // park
        return 4*w;
    endfunction

    // ------------------------------------------------------------------
    // Result table
    // ------------------------------------------------------------------
    localparam int NW = 6;
    string   r_name  [NW];
    string   r_note  [NW];
    longint  r_instr [NW];
    longint  r_cycle [NW];
    longint  r_stall [NW];
    longint  r_flush [NW];
    int      n_res = 0;

    task automatic check_count(input longint actual, input longint expected, input string why);
        checks++;
        if (actual !== expected) begin
            errors++;
            $display("  FAIL: %s (got %0d, expected %0d)", why, actual, expected);
        end
        else $display("  PASS: %s (%0d)", why, actual);
    endtask

    task automatic check_reg(input int idx, input logic [31:0] expected, input string why);
        checks++;
        if (dut.regfile_inst.registers[idx] !== expected) begin
            errors++;
            $display("  FAIL: x%0d = %h, expected %h  (%s)",
                     idx, dut.regfile_inst.registers[idx], expected, why);
        end
        else $display("  PASS: x%0d = %h  (%s)", idx, expected, why);
    endtask

    // Arm the measurement, run until the sentinel commits, and record.
    task automatic measure(input string name, input string note,
                           input int sentinel_pc,
                           input longint exp_instr, exp_stall, exp_flush);
        longint exp_cycle;
        real    cpi;

        bm_sentinel_pc = sentinel_pc;
        bm_armed       = 1'b0;
        bm_captured    = 1'b0;
        late_flushes   = 0;
        bm_active      = 1'b1;

        do_reset();

        fork
            begin : wait_done
                wait (bm_captured == 1'b1);
            end
            begin : timeout
                #200000;
                $display("  FAIL: %s timed out - the sentinel at pc %0d never committed",
                         name, sentinel_pc);
                errors++;
            end
        join_any
        disable fork;

        bm_active = 1'b0;
        #1;

        exp_cycle = 4 + exp_instr + exp_stall + 2*exp_flush;

        $display("---- %s ----", name);
        check_count(cap_instr, exp_instr, "retired instructions (instret_count)");
        check_count(cap_stall, exp_stall, "stall cycles (stall_count)");
        check_count(cap_flush, exp_flush, "flush events (flush_count)");
        check_count(cap_cycle, exp_cycle,
            "cycles (model: 4 fill + retired + stalls + 2 x flushes)");
        check_count(late_flushes, 0,
            "flush events from the drain pad or park inside the window");

        cpi = real'(cap_cycle) / real'(cap_instr);
        $display("  CPI = %0d / %0d = %0.4f", cap_cycle, cap_instr, cpi);

        r_name[n_res]  = name;
        r_note[n_res]  = note;
        r_instr[n_res] = cap_instr;
        r_cycle[n_res] = cap_cycle;
        r_stall[n_res] = cap_stall;
        r_flush[n_res] = cap_flush;
        n_res++;
    endtask

    // ==================================================================
    // Workload programs
    // ==================================================================

    // A. Straight-line independent ALU.
    //    200 ADDIs, each writing a different-ish destination from x0, so
    //    no instruction depends on its neighbour at all. No loads, so no
    //    stalls; no control transfers, so no flushes. This is the pipeline
    //    at its best and the CPI floor for this core.
    localparam int A_N = 200;

    task automatic build_a(output int sentinel_pc, output longint ei, es, ef);
        fill_nops();
        for (int i = 0; i < A_N; i++)
            dut.imem_inst.memory[i] = i_addi(5'((i % 31) + 1), 5'd0, 12'(i & 12'h7FF));
        sentinel_pc = place_tail(A_N);
        ei = A_N + 1;   // the 200 ADDIs plus the sentinel
        es = 0;
        ef = 0;
    endtask

    // B. Load-use.
    //    A two-instruction preamble stores a known value, then 80 back-to-
    //    back (LW x10 / ADDI x11,x10,1) pairs. Every pair is an immediate
    //    load-use dependency and must cost exactly one stall cycle. The
    //    second instruction of pair i and the first of pair i+1 are
    //    independent, so no pair can borrow another's stall.
    localparam int B_PAIRS = 80;

    task automatic build_b(output int sentinel_pc, output longint ei, es, ef);
        int w;
        fill_nops();
        dut.imem_inst.memory[0] = i_addi(5'd1, 5'd0, 12'd7);    // x1 = 7
        dut.imem_inst.memory[1] = i_sw  (5'd1, 5'd0, 12'd4);    // dmem[1] = 7
        w = 2;
        for (int i = 0; i < B_PAIRS; i++) begin
            dut.imem_inst.memory[w]   = i_lw  (5'd10, 5'd0,  12'd4);   // x10 = 7
            dut.imem_inst.memory[w+1] = i_addi(5'd11, 5'd10, 12'd1);   // x11 = 8
            w += 2;
        end
        sentinel_pc = place_tail(w);
        ei = 2 + 2*B_PAIRS + 1;
        es = B_PAIRS;          // one stall cycle per load-use dependency
        ef = 0;
    endtask

    // C. Taken branches.
    //    100 unconditionally-true BEQ x0,x0,+8 at even words. Each one
    //    jumps over the poison at the odd word and lands on the next
    //    branch, so the only instructions that ever retire are the
    //    branches themselves. Nothing else is in the stream, which makes
    //    the measured cost per taken branch unambiguous.
    localparam int C_N = 100;

    task automatic build_c(output int sentinel_pc, output longint ei, es, ef);
        fill_nops();
        for (int i = 0; i < C_N; i++) begin
            dut.imem_inst.memory[2*i]     = i_beq(5'd0, 5'd0, 13'd8);          // taken
            dut.imem_inst.memory[2*i + 1] = i_addi(5'd20, 5'd0, 12'd99);       // POISON
        end
        sentinel_pc = place_tail(2*C_N);
        ei = C_N + 1;
        es = 0;
        ef = C_N;
    endtask

    // C'. Not-taken branches.
    //    The same count of branches, all false (BNE x0,x0), laid out back
    //    to back so every word retires. Each branch targets a poison block
    //    far away, so if the comparison were ever wrong the program would
    //    land in the poison and x20 would be non-zero. Same instruction
    //    count as A, so the difference from A isolates the branch itself
    //    and the difference from C isolates the redirect.
    localparam int D_N       = 200;
    localparam int D_POISON_W = 250;

    task automatic build_d(output int sentinel_pc, output longint ei, es, ef);
        fill_nops();
        for (int i = 0; i < D_N; i++)
            dut.imem_inst.memory[i] = i_bne(5'd0, 5'd0, 13'(4*D_POISON_W - 4*i));
        dut.imem_inst.memory[D_POISON_W] = i_addi(5'd20, 5'd0, 12'd99);        // POISON
        sentinel_pc = place_tail(D_N);
        ei = D_N + 1;
        es = 0;
        ef = 0;                // a not-taken branch raises no redirect
    endtask

    // E. JAL.
    //    100 terminating forward JALs, +8 each, linking into x5. Not a
    //    self-loop: the chain runs off the end into the sentinel, so the
    //    window closes on an architecturally reached instruction.
    localparam int E_N = 100;

    task automatic build_e(output int sentinel_pc, output longint ei, es, ef);
        fill_nops();
        for (int i = 0; i < E_N; i++) begin
            dut.imem_inst.memory[2*i]     = i_jal(5'd5, 21'd8);                // -> next JAL
            dut.imem_inst.memory[2*i + 1] = i_addi(5'd21, 5'd0, 12'd99);       // POISON
        end
        sentinel_pc = place_tail(2*E_N);
        ei = E_N + 1;
        es = 0;
        ef = E_N;
    endtask

    // F. JALR.
    //    100 terminating JALRs. Each uses x0 as its base and an absolute
    //    byte address as its immediate, so the chain needs no setup
    //    instruction and no register dependency: the workload is pure
    //    indirect control transfer. Link goes to x6. Also terminating.
    localparam int F_N = 100;

    task automatic build_f(output int sentinel_pc, output longint ei, es, ef);
        fill_nops();
        for (int i = 0; i < F_N; i++) begin
            dut.imem_inst.memory[2*i]     = i_jalr(5'd6, 5'd0, 12'(8*i + 8));  // -> next JALR
            dut.imem_inst.memory[2*i + 1] = i_addi(5'd22, 5'd0, 12'd99);       // POISON
        end
        sentinel_pc = place_tail(2*F_N);
        ei = F_N + 1;
        es = 0;
        ef = F_N;
    endtask

    // ==================================================================
    initial begin
        int      spc;
        longint  ei, es, ef;
        real     cpi;

        reset = 1'b1;
        bm_active = 1'b0;
        @(negedge clk);

        $display("======== Phase 10.2: CPI workloads ========");

        // ---- A ----
        build_a(spc, ei, es, ef);
        measure("Straight-line", "200 independent ADDI + sentinel", spc, ei, es, ef);
        check_reg(31, 32'd123, "sentinel executed");
        // Spot-check a mid-stream result. Destinations cycle x1..x31, so x14
        // is written by every i with (i % 31) + 1 == 14; the last such i
        // below 200 is 199 (13 + 31*6), and each ADDI stores its own index.
        check_reg(14, 32'd199, "last ADDI targeting x14 (i = 199) left its immediate behind");

        // ---- B ----
        build_b(spc, ei, es, ef);
        measure("Load-use", "80 LW/ADDI dependent pairs", spc, ei, es, ef);
        $display("  load-use dependencies in the program: %0d", B_PAIRS);
        check_count(cap_stall, B_PAIRS,
            "stall_count equals the number of load-use dependencies");
        check_reg(10, 32'd7,  "final LW result");
        check_reg(11, 32'd8,  "final dependent ADDI result");
        check_reg(31, 32'd123, "sentinel executed");

        // ---- C ----
        build_c(spc, ei, es, ef);
        measure("Branch taken", "100 taken BEQ, poison in every shadow", spc, ei, es, ef);
        $display("  taken branches in the program: %0d", C_N);
        check_count(cap_flush, C_N, "flush_count equals the number of taken branches");
        check_reg(20, 32'd0,   "branch-shadow poison never retired");
        check_reg(31, 32'd123, "sentinel executed");

        // ---- D ----
        build_d(spc, ei, es, ef);
        measure("Branch not taken", "200 not-taken BNE", spc, ei, es, ef);
        check_count(cap_flush, 0, "a not-taken branch raises no flush event");
        check_reg(20, 32'd0,   "no branch was taken into the poison block");
        check_reg(31, 32'd123, "sentinel executed");

        // ---- E ----
        build_e(spc, ei, es, ef);
        measure("JAL", "100 terminating forward JAL", spc, ei, es, ef);
        check_count(cap_flush, E_N, "flush_count equals the number of JALs");
        check_reg(21, 32'd0,   "JAL-shadow poison never retired");
        check_reg(5,  32'd4*(2*E_N - 2) + 32'd4, "final JAL link register");
        check_reg(31, 32'd123, "sentinel executed");

        // ---- F ----
        build_f(spc, ei, es, ef);
        measure("JALR", "100 terminating JALR, x0 base", spc, ei, es, ef);
        check_count(cap_flush, F_N, "flush_count equals the number of JALRs");
        check_reg(22, 32'd0,   "JALR-shadow poison never retired");
        check_reg(6,  32'd4*(2*F_N - 2) + 32'd4, "final JALR link register");
        check_reg(31, 32'd123, "sentinel executed");

        // ---- table ----
        $display("");
        $display("======== CPI RESULTS ========");
        $display("| %-16s | %8s | %6s | %11s | %12s | %6s |",
                 "Workload", "Retired", "Cycles", "Stall cycles", "Flush events", "CPI");
        $display("|------------------|----------|--------|-------------|--------------|--------|");
        for (int i = 0; i < n_res; i++) begin
            cpi = real'(r_cycle[i]) / real'(r_instr[i]);
            $display("| %-16s | %8d | %6d | %11d | %12d | %6.4f |",
                     r_name[i], r_instr[i], r_cycle[i], r_stall[i], r_flush[i], cpi);
        end
        $display("");
        for (int i = 0; i < n_res; i++)
            $display("  %-16s : %s", r_name[i], r_note[i]);

        $display("");
        $display("==== cpi bench result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPI_BENCH_TB: ALL PASS");
        else             $display("CPI_BENCH_TB: FAILED");
        $finish;
    end

endmodule
