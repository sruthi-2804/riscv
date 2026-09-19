`timescale 1ns / 1ps
// Full-CPU self-checking testbench for the RV32I subword-memory and U-type
// extension. Loads a directed program hierarchically over the instruction
// memory - no project source file is modified.
//
// Coverage:
//  - LB/LBU at byte offsets 0..3, LH/LHU at both halfword positions
//  - sign extension (0x80 byte, 0xFF byte, 0x80FF half) vs zero extension
//  - LW regression on the same pattern word
//  - SB into each byte lane with all other bytes preserved (cumulative)
//  - SH into both halfword lanes with the other half preserved
//  - LUI exact rd = imm20 << 12 (incl. all-ones imm), AUIPC at non-zero PCs
//    using the pipeline-aligned instruction PC
//  - load-use hazard + forwarding after a subword load (LB -> ADDI, SUB)
//  - x0 write attempt has no effect
//  - JALR with a forwarded target register, wrong-path flush
//  - per-cycle invariants: control_flush never X; bubbles / non-memory
//    instructions carry MEM_WORD + load_unsigned=0 through ID/EX and EX/MEM
//    (no stale subword controls)

module tb_cpu_subword_utype_check;

    logic clk;
    logic reset;

    int errors = 0;
    int checks = 0;
    int inv_errors = 0;

    localparam logic [1:0] MEM_WORD_E  = 2'b10;
    localparam logic [1:0] ALU_A_RS1_E = 2'b00;

    riscv_cpu dut (
        .clk   (clk),
        .reset (reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Load the directed program over the hardcoded one before reset deasserts.
    initial begin
        #1;
        for (int i = 0; i < 256; i++)
            dut.imem_inst.memory[i] = 32'h00000013;           // NOP

        // Build pattern 0x80FF7F01 and store it at dmem word 0
        dut.imem_inst.memory[0]  = 32'h80FF80B7;  // LUI  x1, 0x80FF8
        dut.imem_inst.memory[1]  = 32'hF0108093;  // ADDI x1, x1, -255  -> x1 = 0x80FF7F01
        dut.imem_inst.memory[2]  = 32'h00102023;  // SW   x1, 0(x0)

        // Subword loads from the pattern word
        dut.imem_inst.memory[3]  = 32'h00000103;  // LB  x2, 0(x0)  -> 0x01
        dut.imem_inst.memory[4]  = 32'h00100183;  // LB  x3, 1(x0)  -> 0x7F
        dut.imem_inst.memory[5]  = 32'h00200203;  // LB  x4, 2(x0)  -> 0xFF sign-> -1
        dut.imem_inst.memory[6]  = 32'h00300283;  // LB  x5, 3(x0)  -> 0x80 sign-> -128
        dut.imem_inst.memory[7]  = 32'h00004303;  // LBU x6, 0(x0)  -> 0x01
        dut.imem_inst.memory[8]  = 32'h00104383;  // LBU x7, 1(x0)  -> 0x7F
        dut.imem_inst.memory[9]  = 32'h00204403;  // LBU x8, 2(x0)  -> 0xFF
        dut.imem_inst.memory[10] = 32'h00304483;  // LBU x9, 3(x0)  -> 0x80
        dut.imem_inst.memory[11] = 32'h00001503;  // LH  x10, 0(x0) -> 0x7F01
        dut.imem_inst.memory[12] = 32'h00201583;  // LH  x11, 2(x0) -> 0x80FF sign-> 0xFFFF80FF
        dut.imem_inst.memory[13] = 32'h00005603;  // LHU x12, 0(x0) -> 0x7F01
        dut.imem_inst.memory[14] = 32'h00205683;  // LHU x13, 2(x0) -> 0x80FF
        dut.imem_inst.memory[15] = 32'h00002703;  // LW  x14, 0(x0) -> 0x80FF7F01 (regression)

        // SB into each lane of dmem word 1 (preloaded 0xA5A5A5A5), LW after each
        dut.imem_inst.memory[16] = 32'hA5A5A7B7;  // LUI  x15, 0xA5A5A
        dut.imem_inst.memory[17] = 32'h5A578793;  // ADDI x15, x15, 0x5A5 -> 0xA5A5A5A5
        dut.imem_inst.memory[18] = 32'h00F02223;  // SW   x15, 4(x0)
        dut.imem_inst.memory[19] = 32'h01100813;  // ADDI x16, x0, 0x11
        dut.imem_inst.memory[20] = 32'h01000223;  // SB   x16, 4(x0)   lane 0
        dut.imem_inst.memory[21] = 32'h00402883;  // LW   x17, 4(x0)  -> A5A5A511
        dut.imem_inst.memory[22] = 32'h02200813;  // ADDI x16, x0, 0x22
        dut.imem_inst.memory[23] = 32'h010002A3;  // SB   x16, 5(x0)   lane 1
        dut.imem_inst.memory[24] = 32'h00402903;  // LW   x18, 4(x0)  -> A5A52211
        dut.imem_inst.memory[25] = 32'h03300813;  // ADDI x16, x0, 0x33
        dut.imem_inst.memory[26] = 32'h01000323;  // SB   x16, 6(x0)   lane 2
        dut.imem_inst.memory[27] = 32'h00402983;  // LW   x19, 4(x0)  -> A5332211
        dut.imem_inst.memory[28] = 32'h04400813;  // ADDI x16, x0, 0x44
        dut.imem_inst.memory[29] = 32'h010003A3;  // SB   x16, 7(x0)   lane 3
        dut.imem_inst.memory[30] = 32'h00402A03;  // LW   x20, 4(x0)  -> 44332211

        // SH into both halves of dmem word 2 (preloaded 0x77777777)
        dut.imem_inst.memory[31] = 32'h77777AB7;  // LUI  x21, 0x77777
        dut.imem_inst.memory[32] = 32'h777A8A93;  // ADDI x21, x21, 0x777 -> 0x77777777
        dut.imem_inst.memory[33] = 32'h01502423;  // SW   x21, 8(x0)
        dut.imem_inst.memory[34] = 32'h00001B37;  // LUI  x22, 0x1
        dut.imem_inst.memory[35] = 32'h234B0B13;  // ADDI x22, x22, 0x234 -> 0x1234
        dut.imem_inst.memory[36] = 32'h01601423;  // SH   x22, 8(x0)   lower half
        dut.imem_inst.memory[37] = 32'h00802B83;  // LW   x23, 8(x0)  -> 77771234
        dut.imem_inst.memory[38] = 32'h01601523;  // SH   x22, 10(x0)  upper half
        dut.imem_inst.memory[39] = 32'h00802C03;  // LW   x24, 8(x0)  -> 12341234

        // U-type
        dut.imem_inst.memory[40] = 32'hFFFFFCB7;  // LUI   x25, 0xFFFFF -> 0xFFFFF000
        dut.imem_inst.memory[41] = 32'h00000D17;  // AUIPC x26, 0 -> PC = 164 (0xA4)
        dut.imem_inst.memory[42] = 32'h00001D97;  // AUIPC x27, 1 -> 168 + 0x1000 = 0x10A8

        // Hazards after a subword load
        dut.imem_inst.memory[43] = 32'h00200E03;  // LB   x28, 2(x0)   -> -1
        dut.imem_inst.memory[44] = 32'h001E0E93;  // ADDI x29, x28, 1  -> 0   (load-use)
        dut.imem_inst.memory[45] = 32'h41C48F33;  // SUB  x30, x9, x28 -> 0x80 - (-1) = 0x81

        // x0 must ignore writes
        dut.imem_inst.memory[46] = 32'h03700013;  // ADDI x0, x0, 55

        // AUIPC immediately consumed by a dependent ALU instruction
        dut.imem_inst.memory[47] = 32'h00000817;  // AUIPC x16, 0      -> x16 = 188 (0xBC)
        dut.imem_inst.memory[48] = 32'h00980AB3;  // ADD  x21, x16, x9 -> 0xBC + 0x80 = 0x13C

        // Subword load immediately consumed by a dependent branch
        dut.imem_inst.memory[49] = 32'h00300803;  // LB   x16, 3(x0)   -> 0xFFFFFF80
        dut.imem_inst.memory[50] = 32'h00580463;  // BEQ  x16, x5, +8  -> taken (== -128)
        dut.imem_inst.memory[51] = 32'h06300A93;  // ADDI x21, x0, 99  wrong path - flushed

        // Load immediately feeding a dependent store's data
        dut.imem_inst.memory[52] = 32'h00402803;  // LW   x16, 4(x0)   -> 0x44332211
        dut.imem_inst.memory[53] = 32'h01002623;  // SW   x16, 12(x0)  -> dmem[3]

        // JALR with forwarded target register
        dut.imem_inst.memory[54] = 32'h0E400F93;  // ADDI x31, x0, 228
        dut.imem_inst.memory[55] = 32'h000F80E7;  // JALR x1, 0(x31)   link x1 = 224
        dut.imem_inst.memory[56] = 32'h06300B13;  // ADDI x22, x0, 99  wrong path - flushed
        dut.imem_inst.memory[57] = 32'h04D00793;  // ADDI x15, x0, 77  JALR target
        dut.imem_inst.memory[58] = 32'h0000006F;  // JAL  x0, 0        park in self-loop
    end

    // ------------------------------------------------------------------
    // Committed-store monitor: records store_byte_enable / store_write_data
    // for every write that actually reaches data memory.
    // ------------------------------------------------------------------
    localparam int N_STORES = 10;
    logic [3:0]  exp_be   [N_STORES] = '{4'b1111, 4'b1111, 4'b0001, 4'b0010, 4'b0100,
                                         4'b1000, 4'b1111, 4'b0011, 4'b1100, 4'b1111};
    logic [31:0] exp_sdata[N_STORES] = '{32'h80FF7F01, 32'hA5A5A5A5, 32'h00000011,
                                         32'h00002200, 32'h00330000, 32'h44000000,
                                         32'h77777777, 32'h00001234, 32'h12340000,
                                         32'h44332211};
    int store_count = 0;
    int store_errors = 0;

    always @(posedge clk) begin
        if (!reset && dut.data_mem_write_enable === 1'b1) begin
            if (store_count < N_STORES) begin
                if (dut.store_byte_enable !== exp_be[store_count] ||
                    dut.store_write_data  !== exp_sdata[store_count]) begin
                    store_errors++;
                    $display("STORE FAIL #%0d @%0t: be=%b data=%h, expected be=%b data=%h",
                             store_count, $time, dut.store_byte_enable, dut.store_write_data,
                             exp_be[store_count], exp_sdata[store_count]);
                end
            end
            store_count++;
        end
    end

    // ------------------------------------------------------------------
    // Per-cycle invariants (bug class from the 19-Sep review):
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!reset) begin
            if ($isunknown(dut.control_flush)) begin
                inv_errors++;
                $display("INVARIANT FAIL @%0t: control_flush is X", $time);
            end
            if (dut.id_ex_valid === 1'b1 &&
                dut.id_ex_mem_read === 1'b0 && dut.id_ex_mem_write === 1'b0 &&
                (dut.id_ex_mem_size !== MEM_WORD_E || dut.id_ex_load_unsigned !== 1'b0)) begin
                inv_errors++;
                $display("INVARIANT FAIL @%0t: stale id_ex_mem_size=%b load_unsigned=%b on non-memory instr",
                         $time, dut.id_ex_mem_size, dut.id_ex_load_unsigned);
            end
            if (dut.ex_mem_valid === 1'b1 &&
                dut.ex_mem_mem_read === 1'b0 && dut.ex_mem_mem_write === 1'b0 &&
                (dut.ex_mem_mem_size !== MEM_WORD_E || dut.ex_mem_load_unsigned !== 1'b0)) begin
                inv_errors++;
                $display("INVARIANT FAIL @%0t: stale ex_mem_mem_size=%b load_unsigned=%b on non-memory instr",
                         $time, dut.ex_mem_mem_size, dut.ex_mem_load_unsigned);
            end
            if (dut.id_ex_valid === 1'b0 && dut.id_ex_alu_a_sel !== ALU_A_RS1_E) begin
                inv_errors++;
                $display("INVARIANT FAIL @%0t: bubble carries id_ex_alu_a_sel=%b",
                         $time, dut.id_ex_alu_a_sel);
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

    task automatic check_dmem(input int idx, input logic [31:0] expected, input string why);
        checks++;
        if (dut.dmem_inst.memory[idx] !== expected) begin
            errors++;
            $display("FAIL: dmem[%0d] = %h, expected %h  (%s)",
                     idx, dut.dmem_inst.memory[idx], expected, why);
        end
        else $display("PASS: dmem[%0d] = %h  (%s)", idx, expected, why);
    endtask

    initial begin
        reset = 1'b1;
        #12;
        reset = 1'b0;

        // ~52 instructions + stalls/flushes; 150 cycles is ample.
        #1500;

        $display("==== subword / U-type suite checks ====");

        // LB sign extension at all four offsets
        check_reg(2,  32'h00000001, "LB offset 0: 0x01 -> 1");
        check_reg(3,  32'h0000007F, "LB offset 1: 0x7F -> 127");
        check_reg(4,  32'hFFFFFFFF, "LB offset 2: 0xFF sign-extends to -1");
        check_reg(5,  32'hFFFFFF80, "LB offset 3: 0x80 sign-extends to -128");

        // LBU zero extension at all four offsets
        check_reg(6,  32'h00000001, "LBU offset 0 zero-extends");
        check_reg(7,  32'h0000007F, "LBU offset 1 zero-extends");
        check_reg(8,  32'h000000FF, "LBU offset 2: 0xFF stays 0xFF");
        check_reg(9,  32'h00000080, "LBU offset 3: 0x80 stays 0x80");

        // LH/LHU both positions, negative half 0x80FF
        check_reg(10, 32'h00007F01, "LH lower half: 0x7F01 positive");
        check_reg(11, 32'hFFFF80FF, "LH upper half: 0x80FF sign-extends");
        check_reg(12, 32'h00007F01, "LHU lower half zero-extends");
        check_reg(13, 32'h000080FF, "LHU upper half: 0x80FF stays 0x80FF");

        // LW regression
        check_reg(14, 32'h80FF7F01, "LW still reads the full word");
        check_dmem(0, 32'h80FF7F01, "SW pattern word intact (no SB/SH leakage)");

        // SB lane-by-lane with preservation
        check_reg(17, 32'hA5A5A511, "SB lane 0: bytes 1-3 preserved");
        check_reg(18, 32'hA5A52211, "SB lane 1: bytes 0,2,3 preserved");
        check_reg(19, 32'hA5332211, "SB lane 2: bytes 0,1,3 preserved");
        check_reg(20, 32'h44332211, "SB lane 3: bytes 0-2 preserved");
        check_dmem(1, 32'h44332211, "dmem word after four SBs");

        // SH both halves with preservation
        check_reg(23, 32'h77771234, "SH lower half: upper half preserved");
        check_reg(24, 32'h12341234, "SH upper half: lower half preserved");
        check_dmem(2, 32'h12341234, "dmem word after two SHs");

        // LUI / AUIPC
        check_reg(25, 32'hFFFFF000, "LUI rd = imm20 << 12 exactly (all-ones imm)");
        check_reg(26, 32'h000000A4, "AUIPC uses the AUIPC's own pipeline PC (164)");
        check_reg(27, 32'h000010A8, "AUIPC rd = instr PC 168 + (1 << 12)");

        // Hazards after subword load
        check_reg(28, 32'hFFFFFFFF, "LB for hazard test");
        check_reg(29, 32'h00000000, "load-use stall + forward after LB (-1 + 1)");
        check_reg(30, 32'h00000081, "SUB with forwarded subword-load operand");

        // x0
        check_reg(0,  32'h00000000, "write to x0 ignored");

        // AUIPC -> immediate dependent use (EX/MEM forwarding of AUIPC result)
        check_reg(21, 32'h0000013C, "ADD right after AUIPC uses forwarded AUIPC rd");

        // subword load -> dependent branch (stall + forward into comparator),
        // then load -> dependent store data (stall + forward into store path)
        check_dmem(3, 32'h44332211, "SW data forwarded from immediately preceding LW");
        check_reg(16, 32'h44332211, "LW before dependent SW");

        // JALR with forwarded target
        check_reg(31, 32'd228,      "JALR base register");
        check_reg(1,  32'd224,      "JALR link = pc + 4 (forwarded target)");
        check_reg(22, 32'h00001234, "wrong-path instrs after JALR and LB-BEQ flushed");
        check_reg(15, 32'd77,       "JALR landed at forwarded rs1 target");

        // committed store_byte_enable / store_write_data sequence
        checks++;
        if (store_count !== N_STORES || store_errors !== 0) begin
            errors++;
            $display("FAIL: store monitor saw %0d stores (%0d mismatches), expected %0d clean",
                     store_count, store_errors, N_STORES);
        end
        else $display("PASS: all %0d committed stores had correct byte_enable + positioned data",
                      N_STORES);

        checks++;
        if (inv_errors != 0) begin
            errors++;
            $display("FAIL: %0d per-cycle invariant violations (stale controls / X flush)", inv_errors);
        end
        else $display("PASS: no stale mem_size/load_unsigned/alu_a_sel, control_flush never X");

        $display("==== subword/U-type suite result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_SUBWORD_TB: ALL PASS");
        else             $display("CPU_SUBWORD_TB: FAILED");
        $finish;
    end

endmodule
