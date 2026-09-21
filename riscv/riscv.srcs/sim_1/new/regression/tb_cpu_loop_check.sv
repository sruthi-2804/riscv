`timescale 1ns / 1ps
// Phase 9 closure: backward-branch loop workloads at CPU level.
//
// Programs are assembled with encoder functions rather than hand-written
// hex constants, so branch displacements - especially negative B-type and
// J-type ones - cannot be mis-assembled by hand.
//
// Four programs, each run from a clean reset over the existing memories:
//   A  sum 1..100            single backward BNE loop, 100 iterations
//   B  iterative Fibonacci   10 terms written to data memory
//   C  nested loop           inner and outer backward branches
//   D  long mixed workload   ALU + forwarding + store + load-use + branch
//
// Every loop keeps a shadow counter in the instruction immediately after
// its backward branch. That instruction is fetched on every taken
// iteration and must retire exactly once, so a flush failure shows up as
// a wrong count rather than being silently absorbed.
//
// The load-use stall monitor from the alu/hazard suite is reused here so
// the exactly-one-cycle property is exercised across many events (program
// D alone produces 65) rather than a single one.

module tb_cpu_loop_check;

    logic clk;
    logic reset;

    riscv_cpu dut (
        .clk   (clk),
        .reset (reset)
    );

    int    errors = 0;
    int    checks = 0;
    string cur    = "";

    logic [31:0] prog [0:255];

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------
    // RV32I encoders (same shape as the randomized suite's encoders)
    // ------------------------------------------------------------------
    function automatic logic [31:0] enc_r(input logic [6:0] f7, input logic [4:0] rs2, rs1,
                                          input logic [2:0] f3, input logic [4:0] rd);
        return {f7, rs2, rs1, f3, rd, 7'b0110011};
    endfunction

    function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1,
                                          input logic [2:0] f3, input logic [4:0] rd,
                                          input logic [6:0] opc);
        return {imm, rs1, f3, rd, opc};
    endfunction

    function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2, rs1,
                                          input logic [2:0] f3);
        return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] enc_b(input logic [12:0] imm, input logic [4:0] rs2, rs1,
                                          input logic [2:0] f3);
        return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] enc_j(input logic [20:0] imm, input logic [4:0] rd);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    // readable mnemonics; displacements are in BYTES and may be negative
    function automatic logic [31:0] i_addi(input int rd, rs1, imm);
        return enc_i(12'(imm), 5'(rs1), 3'b000, 5'(rd), 7'b0010011);
    endfunction
    function automatic logic [31:0] i_add(input int rd, rs1, rs2);
        return enc_r(7'h00, 5'(rs2), 5'(rs1), 3'b000, 5'(rd));
    endfunction
    function automatic logic [31:0] i_bne(input int rs1, rs2, off);
        return enc_b(13'(off), 5'(rs2), 5'(rs1), 3'b001);
    endfunction
    function automatic logic [31:0] i_lw(input int rd, rs1, off);
        return enc_i(12'(off), 5'(rs1), 3'b010, 5'(rd), 7'b0000011);
    endfunction
    function automatic logic [31:0] i_sw(input int rs2, rs1, off);
        return enc_s(12'(off), 5'(rs2), 5'(rs1), 3'b010);
    endfunction
    function automatic logic [31:0] i_jal(input int rd, off);
        return enc_j(21'(off), 5'(rd));
    endfunction

    localparam logic [31:0] NOP = 32'h00000013;

    // ------------------------------------------------------------------
    // Per-program monitors
    //
    // back_taken / fwd_taken count branches that resolve TAKEN in EX with
    // id_ex_valid set. A wrong-path instruction can never reach EX with
    // its valid bit set, because control_flush clears IF/ID and ID/EX on
    // the edge after a redirect (bound assertion A6), so these are counts
    // of architecturally executed branches only - never flushed ones.
    // ------------------------------------------------------------------
    int inv_errors;
    int back_taken;
    int fwd_taken;

    int stall_events;
    int stall_run_len;
    int bad_run_errors;
    int pc_freeze_errors;
    int ifid_freeze_errors;
    int idex_bubble_errors;
    int resume_errors;

    logic [31:0] pc_at_stall;
    logic [31:0] ifid_at_stall;
    logic        ifidv_at_stall;
    bit          freeze_due;
    bit          resume_due;

    always @(posedge clk) begin
        if (reset) begin
            stall_run_len = 0;
            freeze_due    = 1'b0;
            resume_due    = 1'b0;
        end
        else begin
            // ---- pipeline invariants ----
            if ($isunknown(dut.control_flush)) begin
                inv_errors++;
                $display("FAIL @%0t [%s]: control_flush is X", $time, cur);
            end
            if (dut.id_ex_valid === 1'b0 &&
                (dut.id_ex_reg_write !== 1'b0 || dut.id_ex_mem_write !== 1'b0 ||
                 dut.id_ex_branch !== 1'b0 || dut.id_ex_jal !== 1'b0 ||
                 dut.id_ex_jalr !== 1'b0)) begin
                inv_errors++;
                $display("FAIL @%0t [%s]: bubble carries live control signals", $time, cur);
            end

            // ---- architectural taken-branch direction census ----
            if (dut.id_ex_valid === 1'b1 && dut.ex_branch_taken === 1'b1) begin
                if (dut.id_ex_immediate[31] === 1'b1) back_taken++;
                else                                  fwd_taken++;
            end

            // ---- load-use stall duration ----
            if (resume_due) begin
                if (dut.id_ex_valid !== 1'b1) begin
                    resume_errors++;
                    $display("FAIL @%0t [%s]: pipeline did not resume after a load-use stall",
                             $time, cur);
                end
                resume_due = 1'b0;
            end

            if (freeze_due) begin
                if (dut.pc_value !== pc_at_stall) begin
                    pc_freeze_errors++;
                    $display("FAIL @%0t [%s]: PC advanced during load-use stall (%h -> %h)",
                             $time, cur, pc_at_stall, dut.pc_value);
                end
                if (dut.if_id_instruction !== ifid_at_stall ||
                    dut.if_id_valid       !== ifidv_at_stall) begin
                    ifid_freeze_errors++;
                    $display("FAIL @%0t [%s]: IF/ID changed during load-use stall", $time, cur);
                end
                if (dut.id_ex_valid !== 1'b0) begin
                    idex_bubble_errors++;
                    $display("FAIL @%0t [%s]: ID/EX not bubbled during load-use stall", $time, cur);
                end
                freeze_due = 1'b0;
                resume_due = 1'b1;
            end

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
                    $display("FAIL @%0t [%s]: load-use stall lasted %0d cycles, expected exactly 1",
                             $time, cur, stall_run_len);
                end
                stall_run_len = 0;
            end
        end
    end

    // ------------------------------------------------------------------
    // Harness
    // ------------------------------------------------------------------
    task automatic clear_prog();
        for (int i = 0; i < 256; i++) prog[i] = NOP;
    endtask

    task automatic run_program(input string name, input int cycles);
        cur = name;

        inv_errors = 0; back_taken = 0; fwd_taken = 0;
        stall_events = 0; bad_run_errors = 0;
        pc_freeze_errors = 0; ifid_freeze_errors = 0;
        idex_bubble_errors = 0; resume_errors = 0;

        reset = 1'b1;
        repeat (2) @(posedge clk);
        for (int i = 0; i < 256; i++) dut.imem_inst.memory[i] = prog[i];
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (cycles) @(posedge clk);

        $display("==== %s ====", name);
    endtask

    task automatic check_reg(input int idx, input logic [31:0] expected, input string why);
        checks++;
        if (dut.regfile_inst.registers[idx] !== expected) begin
            errors++;
            $display("FAIL: [%s] x%0d = %h, expected %h  (%s)",
                     cur, idx, dut.regfile_inst.registers[idx], expected, why);
        end
        else $display("PASS: [%s] x%0d = %h  (%s)", cur, idx, expected, why);
    endtask

    task automatic check_dmem(input int idx, input logic [31:0] expected, input string why);
        checks++;
        if (dut.dmem_inst.memory[idx] !== expected) begin
            errors++;
            $display("FAIL: [%s] dmem[%0d] = %h, expected %h  (%s)",
                     cur, idx, dut.dmem_inst.memory[idx], expected, why);
        end
        else $display("PASS: [%s] dmem[%0d] = %h  (%s)", cur, idx, expected, why);
    endtask

    task automatic check_count(input int actual, expected, input string why);
        checks++;
        if (actual !== expected) begin
            errors++;
            $display("FAIL: [%s] %s (got %0d, expected %0d)", cur, why, actual, expected);
        end
        else $display("PASS: [%s] %s (%0d)", cur, why, actual);
    endtask

    // common per-program hygiene checks
    task automatic check_pipeline_clean(input int exp_back_taken);
        check_count(inv_errors,         0, "valid/bubble invariant violations");
        check_count(bad_run_errors,     0, "load-use stalls not exactly 1 cycle");
        check_count(pc_freeze_errors,   0, "PC-freeze violations");
        check_count(ifid_freeze_errors, 0, "IF/ID-freeze violations");
        check_count(idex_bubble_errors, 0, "ID/EX-bubble violations");
        check_count(resume_errors,      0, "failures to resume after a stall");
        check_count(back_taken, exp_back_taken, "architectural BACKWARD taken branches");
    endtask

    // ------------------------------------------------------------------
    // Programs
    // ------------------------------------------------------------------
    task automatic build_sum_loop();
        clear_prog();
        prog[0] = i_addi(1, 0, 0);      // sum = 0
        prog[1] = i_addi(2, 0, 0);      // i   = 0
        prog[2] = i_addi(3, 0, 100);    // N   = 100
        prog[3] = i_addi(4, 0, 0);      // shadow counter
        // loop:                            [4]
        prog[4] = i_addi(2, 2, 1);      //   i   = i + 1
        prog[5] = i_add (1, 1, 2);      //   sum = sum + i   (forwarded i)
        prog[6] = i_bne (2, 3, -8);     //   BACKWARD -> [4], taken 99 times
        prog[7] = i_addi(4, 4, 1);      // branch shadow: must retire exactly once
        prog[8] = i_jal (0, 0);         // park
    endtask

    task automatic build_fib_loop();
        clear_prog();
        prog[0]  = i_addi(1, 0, 0);     // a = 0
        prog[1]  = i_addi(2, 0, 1);     // b = 1
        prog[2]  = i_addi(3, 0, 0);     // i = 0
        prog[3]  = i_addi(4, 0, 10);    // terms = 10
        prog[4]  = i_addi(5, 0, 0);     // addr = 0
        prog[5]  = i_addi(10, 0, 0);    // shadow counter
        // loop:                            [6]
        prog[6]  = i_add (6, 1, 2);     //   next = a + b
        prog[7]  = i_add (1, 0, 2);     //   a = b
        prog[8]  = i_add (2, 0, 6);     //   b = next   (forwarded next)
        prog[9]  = i_sw  (6, 5, 0);     //   mem[addr] = next
        prog[10] = i_addi(5, 5, 4);     //   addr += 4
        prog[11] = i_addi(3, 3, 1);     //   i += 1
        prog[12] = i_bne (3, 4, -24);   //   BACKWARD -> [6], taken 9 times
        prog[13] = i_addi(10, 10, 1);   // branch shadow: exactly once
        prog[14] = i_lw  (7, 0, 36);    // read back the 10th term
        prog[15] = i_jal (0, 0);        // park
    endtask

    task automatic build_nested_loop();
        clear_prog();
        prog[0]  = i_addi(1, 0, 0);     // total = 0
        prog[1]  = i_addi(2, 0, 0);     // outer i = 0
        prog[2]  = i_addi(3, 0, 5);     // outer N = 5
        prog[3]  = i_addi(5, 0, 7);     // inner N = 7
        prog[4]  = i_addi(6, 0, 0);     // outer-exit shadow
        prog[5]  = i_addi(7, 0, 0);     // inner-exit shadow
        // outer:                           [6]
        prog[6]  = i_addi(4, 0, 0);     //   j = 0
        // inner:                           [7]
        prog[7]  = i_addi(4, 4, 1);     //     j += 1
        prog[8]  = i_addi(1, 1, 1);     //     total += 1
        prog[9]  = i_bne (4, 5, -8);    //     BACKWARD -> [7], taken 6x per outer pass
        prog[10] = i_addi(7, 7, 1);     //   inner shadow: once per outer pass = 5
        prog[11] = i_addi(2, 2, 1);     //   i += 1
        prog[12] = i_bne (2, 3, -24);   //   BACKWARD -> [6], taken 4 times
        prog[13] = i_addi(6, 6, 1);     // outer shadow: exactly once
        prog[14] = i_jal (0, 0);        // park
    endtask

    task automatic build_long_workload();
        clear_prog();
        prog[0]  = i_addi(1, 0, 0);     // checksum = 0
        prog[1]  = i_addi(2, 0, 0);     // i    = 0
        prog[2]  = i_addi(3, 0, 64);    // N    = 64
        prog[3]  = i_addi(4, 0, 0);     // addr = 0
        prog[4]  = i_addi(8, 0, 0);     // shadow counter
        // loop:                            [5]
        prog[5]  = i_add (5, 2, 2);     //   x5 = 2*i
        prog[6]  = i_add (6, 5, 2);     //   x6 = 3*i   (EX/MEM forward of x5)
        prog[7]  = i_sw  (6, 4, 0);     //   mem[addr] = 3*i
        prog[8]  = i_lw  (7, 4, 0);     //   x7 = mem[addr]
        prog[9]  = i_add (1, 1, 7);     //   checksum += x7  (load-use on rs2)
        prog[10] = i_addi(4, 4, 4);     //   addr += 4
        prog[11] = i_addi(2, 2, 1);     //   i += 1
        prog[12] = i_bne (2, 3, -28);   //   BACKWARD -> [5], taken 63 times
        prog[13] = i_addi(8, 8, 1);     // branch shadow: exactly once
        prog[14] = i_lw  (9, 0, 252);   // re-read the last word written
        prog[15] = i_addi(10, 9, 0);    // load-use on rs1
        prog[16] = i_jal (0, 0);        // park
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        reset = 1'b1;

        // ---------------- A: sum 1..100 ----------------
        build_sum_loop();
        run_program("A: sum 1..100 (backward BNE loop)", 1500);

        check_reg(1, 32'd5050, "sum of 1..100");
        check_reg(2, 32'd100,  "loop counter reached N");
        check_reg(3, 32'd100,  "loop bound untouched");
        check_reg(4, 32'd1,    "branch shadow retired once, not 100x");
        check_pipeline_clean(99);
        check_count(stall_events, 0, "load-use stalls (program has no loads)");

        // ---------------- B: Fibonacci ----------------
        build_fib_loop();
        run_program("B: iterative Fibonacci, 10 terms", 500);

        check_reg(1,  32'd55, "a = F(10)");
        check_reg(2,  32'd89, "b = F(11)");
        check_reg(6,  32'd89, "last computed term");
        check_reg(3,  32'd10, "term counter");
        check_reg(5,  32'd40, "store pointer advanced 10 words");
        check_reg(10, 32'd1,  "branch shadow retired once, not 10x");
        check_reg(7,  32'd89, "LW read back the 10th term");
        check_dmem(0, 32'd1,  "term 1 in memory");
        check_dmem(3, 32'd5,  "term 4 in memory");
        check_dmem(4, 32'd8,  "term 5 in memory");
        check_dmem(8, 32'd55, "term 9 in memory");
        check_dmem(9, 32'd89, "term 10 in memory");
        check_pipeline_clean(9);

        // ---------------- C: nested loop ----------------
        build_nested_loop();
        run_program("C: two-level nested loop", 800);

        check_reg(1, 32'd35, "total = outer 5 x inner 7");
        check_reg(2, 32'd5,  "outer counter");
        check_reg(4, 32'd7,  "inner counter at exit");
        check_reg(7, 32'd5,  "inner-exit shadow: once per outer pass");
        check_reg(6, 32'd1,  "outer-exit shadow: exactly once");
        check_pipeline_clean(34);   // inner 6x5 = 30, outer 4

        // ---------------- D: long mixed workload ----------------
        build_long_workload();
        run_program("D: long mixed workload, 64 iterations", 2000);

        check_reg(1,  32'd6048, "checksum = 3 * sum(0..63)");
        check_reg(2,  32'd64,   "iteration count");
        check_reg(4,  32'd256,  "address pointer advanced 64 words");
        check_reg(5,  32'd126,  "2*i on the final iteration");
        check_reg(6,  32'd189,  "3*i on the final iteration");
        check_reg(7,  32'd189,  "value loaded back on the final iteration");
        check_reg(8,  32'd1,    "branch shadow retired once, not 64x");
        check_reg(9,  32'd189,  "final LW re-read the last word");
        check_reg(10, 32'd189,  "load-use consumer after the final LW");
        check_dmem(0,  32'd0,   "first stored word");
        check_dmem(1,  32'd3,   "second stored word");
        check_dmem(10, 32'd30,  "eleventh stored word");
        check_dmem(63, 32'd189, "last stored word");
        check_pipeline_clean(63);
        check_count(stall_events, 65, "load-use stall events (64 in loop + 1 after)");

        $display("==== cpu loop suite result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_LOOP_TB: ALL PASS");
        else             $display("CPU_LOOP_TB: FAILED");
        $finish;
    end

endmodule
