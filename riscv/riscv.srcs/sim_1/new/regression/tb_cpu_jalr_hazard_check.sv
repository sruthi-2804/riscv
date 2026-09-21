`timescale 1ns / 1ps
// Phase 9 closure: JALR corner cases and combined control/hazard paths.
//
// Programs are assembled with encoder functions so displacements cannot be
// mis-assembled by hand. Each program runs from a clean reset.
//
//   P1  canonical load-use    LW xN,off(xM) / ADD consuming xN
//   P2  JALR base forwarded from EX/MEM   (producer at distance 1)
//   P3  JALR base forwarded from MEM/WB   (producer at distance 2)
//   P4  LW -> JALR            load-use stall AND redirect AND link write
//   P5  JALR adjacent to other control flow (branch -> JALR -> JAL)
//
// For the forwarding programs the check is not just "the right target was
// reached": the mux select actually used for the JALR base is captured in
// EX and asserted, so a program that happened to work via the register
// file rather than via forwarding would still fail.

module tb_cpu_jalr_hazard_check;

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
    // RV32I encoders
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

    function automatic logic [31:0] i_addi(input int rd, rs1, imm);
        return enc_i(12'(imm), 5'(rs1), 3'b000, 5'(rd), 7'b0010011);
    endfunction
    function automatic logic [31:0] i_add(input int rd, rs1, rs2);
        return enc_r(7'h00, 5'(rs2), 5'(rs1), 3'b000, 5'(rd));
    endfunction
    function automatic logic [31:0] i_lw(input int rd, rs1, off);
        return enc_i(12'(off), 5'(rs1), 3'b010, 5'(rd), 7'b0000011);
    endfunction
    function automatic logic [31:0] i_sw(input int rs2, rs1, off);
        return enc_s(12'(off), 5'(rs2), 5'(rs1), 3'b010);
    endfunction
    function automatic logic [31:0] i_beq(input int rs1, rs2, off);
        return enc_b(13'(off), 5'(rs2), 5'(rs1), 3'b000);
    endfunction
    function automatic logic [31:0] i_jal(input int rd, off);
        return enc_j(21'(off), 5'(rd));
    endfunction
    function automatic logic [31:0] i_jalr(input int rd, rs1, off);
        return enc_i(12'(off), 5'(rs1), 3'b000, 5'(rd), 7'b1100111);
    endfunction

    localparam logic [31:0] NOP = 32'h00000013;

    // ------------------------------------------------------------------
    // Monitors
    //
    // fwd_probe_pc selects one instruction (by its own PC) whose operand
    // mux selects are captured the cycle it sits in EX. jalr_* capture the
    // first JALR that resolves in EX, which in these programs is the JALR
    // under test.
    // ------------------------------------------------------------------
    logic [31:0] fwd_probe_pc;
    logic [1:0]  fwd_a_seen;
    logic [1:0]  fwd_b_seen;
    bit          fwd_seen;

    logic [31:0] jalr_target_seen;
    logic [1:0]  jalr_fwd_a_seen;
    bit          jalr_seen;

    int stall_events;
    int stall_run_len;
    int bad_run_errors;
    int pc_freeze_errors;
    int ifid_freeze_errors;
    int idex_bubble_errors;
    int resume_errors;
    int inv_errors;

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

            // operand-mux probe for one nominated instruction
            if (dut.id_ex_valid === 1'b1 && dut.id_ex_pc === fwd_probe_pc && !fwd_seen) begin
                fwd_a_seen = dut.forward_a;
                fwd_b_seen = dut.forward_b;
                fwd_seen   = 1'b1;
            end

            // first JALR to resolve in EX
            if (dut.id_ex_valid === 1'b1 && dut.id_ex_jalr === 1'b1 && !jalr_seen) begin
                jalr_target_seen = dut.ex_jalr_target;
                jalr_fwd_a_seen  = dut.forward_a;
                jalr_seen        = 1'b1;
            end

            // load-use stall duration
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

    task automatic run_program(input string name, input int probe_pc, input int cycles);
        cur          = name;
        fwd_probe_pc = 32'(probe_pc);
        fwd_seen     = 1'b0;
        jalr_seen    = 1'b0;
        fwd_a_seen   = 2'b11;
        fwd_b_seen   = 2'b11;
        jalr_fwd_a_seen  = 2'b11;
        jalr_target_seen = 32'hDEADDEAD;

        inv_errors = 0; stall_events = 0; bad_run_errors = 0;
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

    task automatic check_val(input logic [31:0] actual, expected, input string why);
        checks++;
        if (actual !== expected) begin
            errors++;
            $display("FAIL: [%s] %s = %h, expected %h", cur, why, actual, expected);
        end
        else $display("PASS: [%s] %s = %h", cur, why, expected);
    endtask

    task automatic check_count(input int actual, expected, input string why);
        checks++;
        if (actual !== expected) begin
            errors++;
            $display("FAIL: [%s] %s (got %0d, expected %0d)", cur, why, actual, expected);
        end
        else $display("PASS: [%s] %s (%0d)", cur, why, actual);
    endtask

    task automatic check_stall_quality();
        check_count(bad_run_errors,     0, "load-use stalls not exactly 1 cycle");
        check_count(pc_freeze_errors,   0, "PC-freeze violations");
        check_count(ifid_freeze_errors, 0, "IF/ID-freeze violations");
        check_count(idex_bubble_errors, 0, "ID/EX-bubble violations");
        check_count(resume_errors,      0, "failures to resume after the stall");
        check_count(inv_errors,         0, "valid/bubble invariant violations");
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        reset = 1'b1;

        // ------------------------------------------------------------------
        // P1: canonical load-use  LW x5,0(x1) ; ADD x6,x5,x2
        // ------------------------------------------------------------------
        clear_prog();
        prog[0] = i_addi(1, 0, 16);    // base address 16 -> dmem[4]
        prog[1] = i_addi(2, 0, 7);     // addend
        prog[2] = i_addi(3, 0, 100);   // value to store
        prog[3] = i_sw  (3, 1, 0);     // dmem[4] = 100
        prog[4] = i_lw  (5, 1, 0);     // x5 = 100
        prog[5] = i_add (6, 5, 2);     // x6 = x5 + x2 = 107   <- load-use
        prog[6] = i_jal (0, 0);        // park
        run_program("P1: canonical LW -> ADD load-use", 20, 200);

        check_reg(5, 32'd100, "LW produced the stored value");
        check_reg(6, 32'd107, "dependent ADD got the loaded value (100 + 7)");
        check_count(stall_events, 1, "load-use stall events");
        check_val({30'b0, fwd_a_seen}, 32'b01,
                  "dependent ADD took its rs1 from the MEM/WB forwarding path");
        check_stall_quality();

        // ------------------------------------------------------------------
        // P2: JALR base forwarded from EX/MEM (producer immediately before)
        // ------------------------------------------------------------------
        clear_prog();
        prog[0]  = i_addi(5, 0, 40);   // base = 40 -> index 10
        prog[1]  = i_jalr(1, 5, 0);    // pc = 4, link = 8
        prog[2]  = i_addi(20, 0, 99);  // wrong path
        prog[3]  = i_addi(21, 0, 99);  // wrong path
        prog[10] = i_addi(22, 0, 55);  // landing marker
        prog[11] = i_jal (0, 0);       // park
        run_program("P2: JALR base via EX/MEM forwarding", 4, 200);

        check_val(jalr_target_seen, 32'd40, "resolved JALR target");
        check_val({30'b0, jalr_fwd_a_seen}, 32'b10,
                  "JALR base came from the EX/MEM forwarding path");
        check_reg(1,  32'd8,  "link register = pc+4 (4+4)");
        check_reg(22, 32'd55, "execution continued at the JALR target");
        check_reg(20, 32'd0,  "wrong-path instr after JALR flushed");
        check_reg(21, 32'd0,  "second wrong-path instr after JALR flushed");
        check_count(inv_errors, 0, "valid/bubble invariant violations");

        // ------------------------------------------------------------------
        // P3: JALR base forwarded from MEM/WB (one instruction of distance)
        // ------------------------------------------------------------------
        clear_prog();
        prog[0]  = i_addi(5, 0, 40);   // base = 40 -> index 10
        prog[1]  = NOP;                // spacer pushes the producer to MEM/WB
        prog[2]  = i_jalr(1, 5, 0);    // pc = 8, link = 12
        prog[3]  = i_addi(20, 0, 99);  // wrong path
        prog[4]  = i_addi(21, 0, 99);  // wrong path
        prog[10] = i_addi(22, 0, 55);  // landing marker
        prog[11] = i_jal (0, 0);       // park
        run_program("P3: JALR base via MEM/WB forwarding", 8, 200);

        check_val(jalr_target_seen, 32'd40, "resolved JALR target");
        check_val({30'b0, jalr_fwd_a_seen}, 32'b01,
                  "JALR base came from the MEM/WB forwarding path");
        check_reg(1,  32'd12, "link register = pc+4 (8+4)");
        check_reg(22, 32'd55, "execution continued at the JALR target");
        check_reg(20, 32'd0,  "wrong-path instr after JALR flushed");
        check_reg(21, 32'd0,  "second wrong-path instr after JALR flushed");
        check_count(inv_errors, 0, "valid/bubble invariant violations");

        // ------------------------------------------------------------------
        // P4: LW -> JALR. Combines load-use detection, the one-cycle stall,
        // loaded-value availability, redirect, flush and link writeback.
        // ------------------------------------------------------------------
        clear_prog();
        prog[0]  = i_addi(5, 0, 40);   // target value
        prog[1]  = i_sw  (5, 0, 0);    // dmem[0] = 40
        prog[2]  = i_lw  (6, 0, 0);    // x6 = 40
        prog[3]  = i_jalr(1, 6, 0);    // pc = 12, link = 16  <- load-use on the base
        prog[4]  = i_addi(20, 0, 99);  // wrong path
        prog[5]  = i_addi(21, 0, 99);  // wrong path
        prog[10] = i_addi(22, 0, 55);  // landing marker
        prog[11] = i_jal (0, 0);       // park
        run_program("P4: LW -> JALR combined hazard", 12, 200);

        check_count(stall_events, 1, "load-use stall events");
        check_val(jalr_target_seen, 32'd40, "JALR target taken from the loaded value");
        check_val({30'b0, jalr_fwd_a_seen}, 32'b01,
                  "JALR base arrived via MEM/WB after the stall");
        check_reg(1,  32'd16, "link register = pc+4 (12+4)");
        check_reg(6,  32'd40, "loaded base value");
        check_reg(22, 32'd55, "execution continued at the loaded target");
        check_reg(20, 32'd0,  "wrong-path instr after JALR flushed");
        check_reg(21, 32'd0,  "second wrong-path instr after JALR flushed");
        check_stall_quality();

        // ------------------------------------------------------------------
        // P5: JALR packed between two other control transfers, so three
        // redirects happen back to back with only shadow instructions
        // between them.
        // ------------------------------------------------------------------
        clear_prog();
        prog[0]  = i_addi(5, 0, 40);   // JALR target -> index 10
        prog[1]  = i_beq (0, 0, 8);    // taken -> [3]
        prog[2]  = i_addi(20, 0, 99);  // branch shadow
        prog[3]  = i_jalr(1, 5, 0);    // pc = 12, link = 16
        prog[4]  = i_addi(21, 0, 99);  // JALR shadow
        prog[5]  = i_addi(22, 0, 99);  // JALR shadow
        prog[10] = i_addi(23, 0, 55);  // JALR landing
        prog[11] = i_jal (0, 8);       // -> [13]
        prog[12] = i_addi(24, 0, 99);  // JAL shadow
        prog[13] = i_addi(25, 0, 77);  // final marker
        prog[14] = i_jal (0, 0);       // park
        run_program("P5: branch -> JALR -> JAL back to back", 12, 200);

        check_reg(23, 32'd55, "JALR landed correctly when reached via a taken branch");
        check_reg(25, 32'd77, "execution continued past the following JAL");
        check_reg(1,  32'd16, "link register = pc+4 (12+4)");
        check_reg(20, 32'd0,  "branch shadow flushed");
        check_reg(21, 32'd0,  "first JALR shadow flushed");
        check_reg(22, 32'd0,  "second JALR shadow flushed");
        check_reg(24, 32'd0,  "JAL shadow flushed");
        check_count(inv_errors, 0, "valid/bubble invariant violations");

        $display("==== cpu jalr/hazard suite result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_JALR_HAZARD_TB: ALL PASS");
        else             $display("CPU_JALR_HAZARD_TB: FAILED");
        $finish;
    end

endmodule
