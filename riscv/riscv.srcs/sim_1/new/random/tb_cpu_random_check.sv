`timescale 1ns / 1ps
// Phase 9 Task: constrained-random verification with an architectural
// reference model.
//
// Structure:
//  - deterministic xorshift32 PRNG: every program is fully reproducible
//    from its 32-bit seed (independent of simulator RNG state)
//  - generator emits ONLY instructions the RTL implements, with legal
//    operands: loads/stores are x0-based with size-aligned in-range
//    offsets; branches/JAL jump forward only (guaranteed termination);
//    JALR is emitted as an "ADDI base, x0, target ; JALR rd, 0(base)"
//    pair so its target is always a legal forward program address
//  - reference model: 32 regs (x0 pinned to 0), PC control flow, 256-word
//    data memory, RV32I semantics for every implemented instruction
//  - after each program the DUT's committed architectural state (register
//    file + data memory) is compared against the model; transient pipeline
//    state is never compared, so bubbles/flushed instructions cannot be
//    mistaken for retired ones
//
// Reproduce one failing program:
//   xelab tb_cpu_random_check -R -testplusarg ONLY_SEED=<seed> \
//         -testplusarg ONLY_PHASE=<phase> -testplusarg ONLY_LEN=<len>

module tb_cpu_random_check;

    logic clk;
    logic reset;

    riscv_cpu dut (.clk(clk), .reset(reset));

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------
    // Deterministic PRNG
    // ------------------------------------------------------------------
    int unsigned prng;

    function automatic int unsigned rnd32();
        prng ^= prng << 13;
        prng ^= prng >> 17;
        prng ^= prng << 5;
        return prng;
    endfunction

    // uniform in [0, n-1]
    function automatic int unsigned rnd(input int unsigned n);
        return rnd32() % n;
    endfunction

    // ------------------------------------------------------------------
    // Encoders (RV32I)
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

    function automatic logic [31:0] enc_u(input logic [19:0] imm, input logic [4:0] rd,
                                          input logic [6:0] opc);
        return {imm, rd, opc};
    endfunction

    function automatic logic [31:0] enc_j(input logic [20:0] imm, input logic [4:0] rd);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    localparam logic [31:0] NOP = 32'h00000013;

    // ------------------------------------------------------------------
    // Program generation
    // ------------------------------------------------------------------
    logic [31:0] prog [0:255];
    bit          jalr_2nd [0:255];   // slots holding a JALR (2nd half of pair)
    int          park;               // index of the parking JAL x0,0

    // generated-category counters (whole run)
    int cnt_alu_r, cnt_alu_i, cnt_shift, cnt_cmp, cnt_utype;
    int cnt_load, cnt_store, cnt_branch, cnt_jal, cnt_jalr, cnt_loaduse;

    // pick a forward target index in (idx, len], avoiding JALR 2nd halves
    function automatic int pick_target(input int idx, input int len);
        int j;
        for (int t = 0; t < 8; t++) begin
            j = idx + 1 + rnd(len - idx);
            if (!jalr_2nd[j]) return j;
        end
        return len;   // park is always safe
    endfunction

    // dependency bias: prefer the last written register as a source
    int last_rd;

    function automatic logic [4:0] pick_rs(input int dep_pct);
        if (last_rd != 0 && rnd(100) < dep_pct) return last_rd[4:0];
        return rnd(32);
    endfunction

    // Build one program. Returns nothing; fills prog[], jalr_2nd[], park.
    task automatic gen_program(input int phase, input int len);
        int idx;
        int cat;
        logic [4:0] rd, rs1, rs2, base;
        logic [2:0] f3;
        int dep_pct;
        int target;
        logic [11:0] off;

        for (int i = 0; i < 256; i++) begin
            prog[i]     = NOP;
            jalr_2nd[i] = 1'b0;
        end
        park       = len;
        prog[park] = enc_j(21'd0, 5'd0);   // JAL x0, 0 : park in self-loop
        last_rd    = 0;

        dep_pct = (phase == 1) ? 20 : (phase == 2 || phase == 4) ? 60 : 40;

        idx = 0;
        while (idx < len) begin
            // category roulette per phase (percent thresholds)
            int r = rnd(100);
            case (phase)
                1: cat = (r < 40) ? 0 : (r < 80) ? 1 : 2;                  // R / I / U
                2: cat = (r < 45) ? 0 : (r < 90) ? 1 : 2;
                3: cat = (r < 30) ? 3 : (r < 60) ? 4 : (r < 75) ? 0 : (r < 90) ? 1 : 2;
                4: cat = (r < 35) ? 3 : (r < 55) ? 4 : (r < 95) ? ((r & 1) ? 0 : 1) : 2;
                5: cat = (r < 25) ? 5 : (r < 80) ? ((r & 1) ? 0 : 1) : (r < 90) ? 2 : 3;
                6: cat = (r < 15) ? 6 : (r < 30) ? 7 : (r < 80) ? ((r & 1) ? 0 : 1) : 3;
                default:
                   cat = (r < 15) ? 0 : (r < 30) ? 1 : (r < 38) ? 2 : (r < 53) ? 3 :
                         (r < 65) ? 4 : (r < 80) ? 5 : (r < 90) ? 6 : 7;
            endcase

            // a JALR pair needs two slots
            if (cat == 7 && idx >= len - 1) cat = 0;

            case (cat)
                // -------- R-type ALU (arith/logic/shift/compare) --------
                0: begin
                    int op = rnd(10);
                    rd  = rnd(32); rs1 = pick_rs(dep_pct); rs2 = pick_rs(dep_pct);
                    case (op)
                        0: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b000, rd); cnt_alu_r++; end // ADD
                        1: begin prog[idx] = enc_r(7'h20, rs2, rs1, 3'b000, rd); cnt_alu_r++; end // SUB
                        2: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b111, rd); cnt_alu_r++; end // AND
                        3: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b110, rd); cnt_alu_r++; end // OR
                        4: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b100, rd); cnt_alu_r++; end // XOR
                        5: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b001, rd); cnt_shift++; end // SLL
                        6: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b101, rd); cnt_shift++; end // SRL
                        7: begin prog[idx] = enc_r(7'h20, rs2, rs1, 3'b101, rd); cnt_shift++; end // SRA
                        8: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b010, rd); cnt_cmp++;  end // SLT
                        9: begin prog[idx] = enc_r(7'h00, rs2, rs1, 3'b011, rd); cnt_cmp++;  end // SLTU
                    endcase
                    last_rd = rd;
                end

                // -------- I-type ALU --------
                1: begin
                    int op = rnd(9);
                    logic [4:0] sh;
                    rd = rnd(32); rs1 = pick_rs(dep_pct); sh = rnd(32);
                    case (op)
                        0: begin prog[idx] = enc_i(rnd32(), rs1, 3'b000, rd, 7'b0010011); cnt_alu_i++; end // ADDI
                        1: begin prog[idx] = enc_i(rnd32(), rs1, 3'b111, rd, 7'b0010011); cnt_alu_i++; end // ANDI
                        2: begin prog[idx] = enc_i(rnd32(), rs1, 3'b110, rd, 7'b0010011); cnt_alu_i++; end // ORI
                        3: begin prog[idx] = enc_i(rnd32(), rs1, 3'b100, rd, 7'b0010011); cnt_alu_i++; end // XORI
                        4: begin prog[idx] = enc_i({7'h00, sh}, rs1, 3'b001, rd, 7'b0010011); cnt_shift++; end // SLLI
                        5: begin prog[idx] = enc_i({7'h00, sh}, rs1, 3'b101, rd, 7'b0010011); cnt_shift++; end // SRLI
                        6: begin prog[idx] = enc_i({7'h20, sh}, rs1, 3'b101, rd, 7'b0010011); cnt_shift++; end // SRAI
                        7: begin prog[idx] = enc_i(rnd32(), rs1, 3'b010, rd, 7'b0010011); cnt_cmp++; end // SLTI
                        8: begin prog[idx] = enc_i(rnd32(), rs1, 3'b011, rd, 7'b0010011); cnt_cmp++; end // SLTIU
                    endcase
                    last_rd = rd;
                end

                // -------- LUI / AUIPC --------
                2: begin
                    rd = rnd(32);
                    if (rnd(2)) prog[idx] = enc_u(rnd32(), rd, 7'b0110111);
                    else        prog[idx] = enc_u(rnd32(), rd, 7'b0010111);
                    cnt_utype++;
                    last_rd = rd;
                end

                // -------- load (x0-based, aligned, in-range) --------
                3: begin
                    int lop = rnd(5);
                    rd = rnd(32);
                    case (lop)
                        0: begin off = rnd(1024);          f3 = 3'b000; end // LB
                        1: begin off = rnd(512) * 2;       f3 = 3'b001; end // LH
                        2: begin off = rnd(256) * 4;       f3 = 3'b010; end // LW
                        3: begin off = rnd(1024);          f3 = 3'b100; end // LBU
                        4: begin off = rnd(512) * 2;       f3 = 3'b101; end // LHU
                    endcase
                    prog[idx] = enc_i(off, 5'd0, f3, rd, 7'b0000011);
                    cnt_load++;
                    last_rd = rd;
                    // load-use bias: often make the next instruction consume rd
                    if (rd != 0 && idx + 1 < len && rnd(100) < dep_pct) begin
                        idx++;
                        prog[idx] = enc_i(rnd32(), rd, 3'b000, rnd(32), 7'b0010011); // ADDI rdX, rd, imm
                        cnt_alu_i++;
                        cnt_loaduse++;
                    end
                end

                // -------- store (x0-based, aligned, in-range) --------
                4: begin
                    int sop = rnd(3);
                    rs2 = pick_rs(dep_pct);
                    case (sop)
                        0: begin off = rnd(1024);    f3 = 3'b000; end // SB
                        1: begin off = rnd(512) * 2; f3 = 3'b001; end // SH
                        2: begin off = rnd(256) * 4; f3 = 3'b010; end // SW
                    endcase
                    prog[idx] = enc_s(off, rs2, 5'd0, f3);
                    cnt_store++;
                end

                // -------- branch (forward only) --------
                5: begin
                    logic [2:0] bf3;
                    int bop = rnd(6);
                    case (bop)
                        0: bf3 = 3'b000; 1: bf3 = 3'b001; 2: bf3 = 3'b100;
                        3: bf3 = 3'b101; 4: bf3 = 3'b110; default: bf3 = 3'b111;
                    endcase
                    rs1 = pick_rs(dep_pct); rs2 = pick_rs(dep_pct);
                    target = pick_target(idx, len);
                    prog[idx] = enc_b((target - idx) * 4, rs2, rs1, bf3);
                    cnt_branch++;
                end

                // -------- JAL (forward only) --------
                6: begin
                    rd = rnd(32);
                    target = pick_target(idx, len);
                    prog[idx] = enc_j((target - idx) * 4, rd);
                    cnt_jal++;
                    last_rd = rd;
                end

                // -------- JALR pair: ADDI base,x0,target*4 ; JALR rd,0(base) --------
                7: begin
                    base = 1 + rnd(31);            // never x0
                    target = pick_target(idx + 1, len);
                    prog[idx] = enc_i(target * 4, 5'd0, 3'b000, base, 7'b0010011);
                    idx++;
                    rd = rnd(32);
                    prog[idx] = enc_i(12'd0, base, 3'b000, rd, 7'b1100111);
                    jalr_2nd[idx] = 1'b1;
                    cnt_jalr++;
                    last_rd = rd;
                end
            endcase
            idx++;
        end

        // Post-pass: jalr_2nd[] fills progressively, so an early branch/JAL
        // may target a slot that later became a JALR pair's second half
        // (whose base register is only valid via its own ADDI). Retarget
        // any such control transfer to the park slot.
        for (int i = 0; i < len; i++) begin
            logic [31:0] w2 = prog[i];
            int tgt;
            if (w2[6:0] == 7'b1100011) begin
                tgt = i + ({{19{w2[31]}}, w2[31], w2[7], w2[30:25], w2[11:8], 1'b0} >> 2);
                if (jalr_2nd[tgt]) prog[i] = enc_b((park - i) * 4, w2[24:20], w2[19:15], w2[14:12]);
            end
            else if (w2[6:0] == 7'b1101111 && i != park) begin
                tgt = i + ({{11{w2[31]}}, w2[31], w2[19:12], w2[20], w2[30:21], 1'b0} >> 2);
                if (jalr_2nd[tgt]) prog[i] = enc_j((park - i) * 4, w2[11:7]);
            end
            else if (jalr_2nd[i]) begin
                // pair's target lives in the preceding ADDI's immediate
                logic [31:0] wa = prog[i-1];
                tgt = wa[31:20] >> 2;
                if (jalr_2nd[tgt])
                    prog[i-1] = enc_i(park * 4, 5'd0, 3'b000, wa[11:7], 7'b0010011);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Architectural reference model
    // ------------------------------------------------------------------
    logic [31:0] ref_regs [0:31];
    logic [31:0] ref_mem  [0:255];
    int          ref_steps;
    bit          ref_genbug;
    int          ref_taken, ref_flushes;   // executed control transfers

    function automatic logic [31:0] sx12(input logic [11:0] v);
        return {{20{v[11]}}, v};
    endfunction

    task automatic ref_run();
        logic [31:0] pc, instr, a, b, res, addr, w;
        logic [6:0]  opc;
        logic [2:0]  f3;
        logic [6:0]  f7;
        logic [4:0]  rd, rs1, rs2;
        logic [31:0] imm;
        bit          wr;
        bit          br_taken;

        for (int i = 0; i < 32;  i++) ref_regs[i] = 32'b0;
        for (int i = 0; i < 256; i++) ref_mem[i]  = 32'b0;
        ref_steps = 0; ref_genbug = 0; ref_taken = 0; ref_flushes = 0;

        pc = 32'b0;
        while (pc != park * 4) begin
            if (pc[1:0] != 0 || pc > park * 4 || ref_steps > 4 * park + 64) begin
                ref_genbug = 1;
                return;
            end
            instr = prog[pc[9:2]];
            opc = instr[6:0]; f3 = instr[14:12]; f7 = instr[31:25];
            rd = instr[11:7]; rs1 = instr[19:15]; rs2 = instr[24:20];
            a = ref_regs[rs1]; b = ref_regs[rs2];
            wr = 0; res = '0;

            case (opc)
                7'b0110011: begin // R-type
                    wr = 1;
                    case (f3)
                        3'b000: res = (f7 == 7'h20) ? (a - b) : (a + b);
                        3'b001: res = a << b[4:0];
                        3'b010: res = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
                        3'b011: res = (a < b) ? 32'd1 : 32'd0;
                        3'b100: res = a ^ b;
                        // NOTE: must be if/else, not a ternary - an unsigned
                        // ternary branch would strip $signed() and turn >>>
                        // into a logical shift (found by random testing).
                        3'b101: if (f7 == 7'h20) res = $signed(a) >>> b[4:0];
                                else             res = a >> b[4:0];
                        3'b110: res = a | b;
                        3'b111: res = a & b;
                    endcase
                    pc += 4;
                end
                7'b0010011: begin // I-type ALU
                    imm = sx12(instr[31:20]);
                    wr = 1;
                    case (f3)
                        3'b000: res = a + imm;
                        3'b001: res = a << instr[24:20];
                        3'b010: res = ($signed(a) < $signed(imm)) ? 32'd1 : 32'd0;
                        3'b011: res = (a < imm) ? 32'd1 : 32'd0;
                        3'b100: res = a ^ imm;
                        3'b101: if (instr[30]) res = $signed(a) >>> instr[24:20];
                                else           res = a >> instr[24:20];
                        3'b110: res = a | imm;
                        3'b111: res = a & imm;
                    endcase
                    pc += 4;
                end
                7'b0110111: begin wr = 1; res = {instr[31:12], 12'b0}; pc += 4; end       // LUI
                7'b0010111: begin wr = 1; res = pc + {instr[31:12], 12'b0}; pc += 4; end  // AUIPC
                7'b0000011: begin // loads
                    addr = a + sx12(instr[31:20]);
                    if (addr > 1023 ||
                        (f3 inside {3'b001, 3'b101} && addr[0]) ||
                        (f3 == 3'b010 && addr[1:0] != 0)) begin ref_genbug = 1; return; end
                    w = ref_mem[addr[9:2]];
                    wr = 1;
                    case (f3)
                        3'b000: case (addr[1:0])
                                  2'b00: res = {{24{w[7]}},  w[7:0]};
                                  2'b01: res = {{24{w[15]}}, w[15:8]};
                                  2'b10: res = {{24{w[23]}}, w[23:16]};
                                  2'b11: res = {{24{w[31]}}, w[31:24]};
                                endcase
                        3'b001: res = addr[1] ? {{16{w[31]}}, w[31:16]} : {{16{w[15]}}, w[15:0]};
                        3'b010: res = w;
                        3'b100: case (addr[1:0])
                                  2'b00: res = {24'b0, w[7:0]};
                                  2'b01: res = {24'b0, w[15:8]};
                                  2'b10: res = {24'b0, w[23:16]};
                                  2'b11: res = {24'b0, w[31:24]};
                                endcase
                        3'b101: res = addr[1] ? {16'b0, w[31:16]} : {16'b0, w[15:0]};
                        default: begin ref_genbug = 1; return; end
                    endcase
                    pc += 4;
                end
                7'b0100011: begin // stores
                    addr = a + sx12({instr[31:25], instr[11:7]});
                    if (addr > 1023 ||
                        (f3 == 3'b001 && addr[0]) ||
                        (f3 == 3'b010 && addr[1:0] != 0)) begin ref_genbug = 1; return; end
                    w = ref_mem[addr[9:2]];
                    case (f3)
                        3'b000: case (addr[1:0])
                                  2'b00: w[7:0]   = b[7:0];
                                  2'b01: w[15:8]  = b[7:0];
                                  2'b10: w[23:16] = b[7:0];
                                  2'b11: w[31:24] = b[7:0];
                                endcase
                        3'b001: if (addr[1]) w[31:16] = b[15:0]; else w[15:0] = b[15:0];
                        3'b010: w = b;
                        default: begin ref_genbug = 1; return; end
                    endcase
                    ref_mem[addr[9:2]] = w;
                    pc += 4;
                end
                7'b1100011: begin // branches
                    case (f3)
                        3'b000: br_taken = (a == b);
                        3'b001: br_taken = (a != b);
                        3'b100: br_taken = ($signed(a) < $signed(b));
                        3'b101: br_taken = ($signed(a) >= $signed(b));
                        3'b110: br_taken = (a < b);
                        3'b111: br_taken = (a >= b);
                        default: begin ref_genbug = 1; return; end
                    endcase
                    if (br_taken) begin
                        pc += {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                        ref_taken++; ref_flushes++;
                    end
                    else pc += 4;
                end
                7'b1101111: begin // JAL
                    wr = 1; res = pc + 4;
                    pc += {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
                    ref_flushes++;
                end
                7'b1100111: begin // JALR
                    wr = 1; res = pc + 4;
                    pc = (a + sx12(instr[31:20])) & 32'hFFFFFFFE;
                    ref_flushes++;
                end
                default: begin ref_genbug = 1; return; end
            endcase

            if (wr && rd != 0) ref_regs[rd] = res;
            ref_regs[0] = 32'b0;
            ref_steps++;
        end
    endtask

    // ------------------------------------------------------------------
    // Run one program on the DUT and compare architectural state
    // ------------------------------------------------------------------
    int total_progs, total_instrs, total_fails, total_genbugs;
    int total_taken, total_flushes;
    int fail_seeds  [0:31];
    int fail_phases [0:31];
    int fail_lens   [0:31];

    task automatic run_one(input int unsigned seed, input int phase, input int len);
        int cycles;
        bit mismatch;
        string first_div;

        prng = seed;
        gen_program(phase, len);
        ref_run();

        if (ref_genbug) begin
            total_genbugs++;
            $display("GEN-BUG (classification 2/3): seed=%0d phase=%0d len=%0d -- program skipped", seed, phase, len);
            return;
        end

        // reset DUT and load the program while reset is asserted; deassert
        // on a negedge so reset never races the DUT's posedge processes
        reset = 1'b1;
        repeat (2) @(posedge clk);
        for (int i = 0; i < 256; i++) dut.imem_inst.memory[i] = prog[i];
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        cycles = 4 * ref_steps + 80;
        repeat (cycles) @(posedge clk);

        mismatch = 0; first_div = "";
        for (int i = 0; i < 32; i++) begin
            if (dut.regfile_inst.registers[i] !== ref_regs[i]) begin
                if (!mismatch) first_div = $sformatf("x%0d: expected %h actual %h",
                                  i, ref_regs[i], dut.regfile_inst.registers[i]);
                mismatch = 1;
            end
        end
        for (int i = 0; i < 256; i++) begin
            if (dut.dmem_inst.memory[i] !== ref_mem[i]) begin
                if (!mismatch) first_div = $sformatf("dmem[%0d]: expected %h actual %h",
                                  i, ref_mem[i], dut.dmem_inst.memory[i]);
                mismatch = 1;
            end
        end

        total_progs++;
        total_instrs  += ref_steps;
        total_taken   += ref_taken;
        total_flushes += ref_flushes;

        if (mismatch) begin
            if (total_fails < 32) begin
                fail_seeds[total_fails]  = seed;
                fail_phases[total_fails] = phase;
                fail_lens[total_fails]   = len;
            end
            total_fails++;
            $display("RANDOM FAIL: seed=%0d phase=%0d len=%0d steps=%0d", seed, phase, len, ref_steps);
            $display("  first divergence: %s", first_div);
            $display("  program (idx: instr):");
            for (int i = 0; i <= park; i++)
                if (prog[i] !== NOP || i == park) $display("    %0d: %h", i, prog[i]);
            $display("  full expected vs actual registers:");
            for (int i = 0; i < 32; i++)
                if (dut.regfile_inst.registers[i] !== ref_regs[i])
                    $display("    x%0d exp=%h act=%h", i, ref_regs[i], dut.regfile_inst.registers[i]);
            for (int i = 0; i < 256; i++)
                if (dut.dmem_inst.memory[i] !== ref_mem[i])
                    $display("    dmem[%0d] exp=%h act=%h", i, ref_mem[i], dut.dmem_inst.memory[i]);
            $display("  reproduce: -testplusarg ONLY_SEED=%0d -testplusarg ONLY_PHASE=%0d -testplusarg ONLY_LEN=%0d",
                     seed, phase, len);
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    int unsigned base_seed = 32'd20260919;
    int progs_per_phase [1:7] = '{40, 40, 40, 40, 40, 40, 60};
    int len_per_phase   [1:7] = '{20, 25, 25, 30, 30, 30, 40};

    initial begin
        int unsigned only_seed;
        int only_phase, only_len;
        int unsigned s;

        reset = 1'b1;

        if ($value$plusargs("ONLY_SEED=%d", only_seed)) begin
            only_phase = 7; only_len = 40;
            void'($value$plusargs("ONLY_PHASE=%d", only_phase));
            void'($value$plusargs("ONLY_LEN=%d", only_len));
            $display("== single-program reproduction: seed=%0d phase=%0d len=%0d ==",
                     only_seed, only_phase, only_len);
            run_one(only_seed, only_phase, only_len);
        end
        else begin
            void'($value$plusargs("BASE_SEED=%d", base_seed));
            $display("== randomized run: base_seed=%0d ==", base_seed);
            for (int ph = 1; ph <= 7; ph++) begin
                for (int i = 0; i < progs_per_phase[ph]; i++) begin
                    s = base_seed ^ (ph * 100000 + i * 7919);
                    run_one(s, ph, len_per_phase[ph]);
                end
                $display("phase %0d done: cumulative programs=%0d instrs=%0d fails=%0d",
                         ph, total_progs, total_instrs, total_fails);
            end
        end

        $display("==== random/reference summary ====");
        $display("programs run      : %0d", total_progs);
        $display("instructions run  : %0d (reference-retired)", total_instrs);
        $display("failures          : %0d", total_fails);
        $display("generator skips   : %0d", total_genbugs);
        $display("generated mix     : aluR=%0d aluI=%0d shift=%0d cmp=%0d U=%0d load=%0d store=%0d br=%0d jal=%0d jalr=%0d loaduse-pairs=%0d",
                 cnt_alu_r, cnt_alu_i, cnt_shift, cnt_cmp, cnt_utype,
                 cnt_load, cnt_store, cnt_branch, cnt_jal, cnt_jalr, cnt_loaduse);
        $display("control flow      : taken-branches=%0d total-flushing-transfers=%0d",
                 total_taken, total_flushes);
        for (int i = 0; i < ((total_fails < 32) ? total_fails : 32); i++)
            $display("repro[%0d]: seed=%0d phase=%0d len=%0d", i, fail_seeds[i], fail_phases[i], fail_lens[i]);
        if (total_fails == 0) $display("CPU_RANDOM_TB: ALL PASS");
        else                  $display("CPU_RANDOM_TB: FAILED");
        $finish;
    end

endmodule
