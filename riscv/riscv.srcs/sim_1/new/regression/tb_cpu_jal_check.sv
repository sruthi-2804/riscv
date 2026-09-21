`timescale 1ns / 1ps
// Full-CPU testbench: JAL/JALR, SW/LW regression, load-use hazard, plus basic
// checks of the now-implemented LUI/AUIPC/LB/LH/LBU/LHU/SB/SH instructions.
// (Expectations updated from the old "placeholder does nothing" behavior.)
// The test program is loaded into the existing instruction memory hierarchically
// from this testbench - no project source file is modified.
//
// Phase 9 closure additions:
//  - case 2: a terminating BACKWARD JAL, the only place in the suite that
//    exercises IMM_J sign extension with a negative offset; the link value
//    and the flush of the backward jump's shadow are both checked
//  - case 3: a JALR whose rs1 + immediate is ODD, proving the target is
//    masked to (rs1 + imm) & ~1. Because instruction fetch indexes on
//    address[9:2], an unmasked odd PC would still land on the right word,
//    so the resolved target is captured directly from the EX stage and a
//    PC-alignment invariant runs every cycle.
//  - case 5: loads placed immediately before instructions whose rs1/rs2
//    BIT FIELDS alias the load's rd but are not source operands (LUI,
//    AUIPC, JAL, and an I-type whose immediate occupies the rs2 field).
//    A naive bit-field comparison would stall on all four; the hazard
//    unit must not.

module tb_cpu_jal_check;

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

    // Load the directed program over the hardcoded one before reset deasserts.
    initial begin
        #1;
        for (int i = 0; i < 256; i++)
            dut.imem_inst.memory[i] = 32'h00000013;          // NOP (ADDI x0,x0,0)

        dut.imem_inst.memory[0]  = 32'h00500093;  // ADDI x1,  x0, 5
        dut.imem_inst.memory[1]  = 32'h00C002EF;  // JAL  x5, +12      (pc=4 -> 16, x5 = 8)
        dut.imem_inst.memory[2]  = 32'h06300A13;  // ADDI x20, x0, 99  flushed
        dut.imem_inst.memory[3]  = 32'h06300A93;  // ADDI x21, x0, 99  flushed
        dut.imem_inst.memory[4]  = 32'h00102223;  // SW   x1, 4(x0)    dmem[1] = 5
        dut.imem_inst.memory[5]  = 32'h00402703;  // LW   x14, 4(x0)   x14 = 5
        dut.imem_inst.memory[6]  = 32'h001707B3;  // ADD  x15, x14, x1 x15 = 10 (load-use hazard)
        dut.imem_inst.memory[7]  = 32'h123453B7;  // LUI   x7, 0x12345  x7 = 0x12345000
        dut.imem_inst.memory[8]  = 32'h00001417;  // AUIPC x8, 1        x8 = 32 + 0x1000
        dut.imem_inst.memory[9]  = 32'h00000483;  // LB    x9, 0(x0)    dmem[0]=0 -> 0
        dut.imem_inst.memory[10] = 32'h00001503;  // LH   x10, 0(x0)    dmem[0]=0 -> 0
        dut.imem_inst.memory[11] = 32'h00004583;  // LBU  x11, 0(x0)    dmem[0]=0 -> 0
        dut.imem_inst.memory[12] = 32'h00005603;  // LHU  x12, 0(x0)    dmem[0]=0 -> 0
        dut.imem_inst.memory[13] = 32'h00100423;  // SB   x1, 8(x0)     dmem[2] = 0x05 (byte 0 only)
        dut.imem_inst.memory[14] = 32'h00101623;  // SH   x1, 12(x0)    dmem[3] = 0x0005 (half 0 only)
        dut.imem_inst.memory[15] = 32'h00D00693;  // ADDI x13, x0, 13   marker after placeholders
        dut.imem_inst.memory[16] = 32'h06000113;  // ADDI x2,  x0, 96
        dut.imem_inst.memory[17] = 32'h00410FE7;  // JALR x31, 4(x2)    (pc=68 -> 100, x31 = 72)
        dut.imem_inst.memory[18] = 32'h06300B13;  // ADDI x22, x0, 99   flushed
        dut.imem_inst.memory[19] = 32'h06300B93;  // ADDI x23, x0, 99   flushed
        dut.imem_inst.memory[25] = 32'h03700C13;  // ADDI x24, x0, 55   JALR landing marker

        // ----------------------------------------------------------------
        // Case 2: terminating BACKWARD JAL (negative J-type immediate).
        // Flow: [26] -> [27] jumps forward to [31]; [31] jumps BACKWARD to
        // [28]; [28] marks x25; [29] jumps forward to [32], which runs once
        // and parks. The block therefore terminates - no self-loop is used.
        // [30] is only reachable on a wrong path, and x28 counts [32]'s
        // retirements: 22 means the backward jump's shadow was flushed,
        // 44 would mean it was not.
        // ----------------------------------------------------------------
        dut.imem_inst.memory[26] = 32'h00000E13;  // ADDI x28, x0, 0    shadow counter = 0
        dut.imem_inst.memory[27] = 32'h0100006F;  // JAL  x0,  +16      -> [31]
        dut.imem_inst.memory[28] = 32'h02900C93;  // ADDI x25, x0, 41   backward-JAL landing
        dut.imem_inst.memory[29] = 32'h00C0006F;  // JAL  x0,  +12      -> [32]
        dut.imem_inst.memory[30] = 32'h06300D13;  // ADDI x26, x0, 99   poison (unreachable)
        dut.imem_inst.memory[31] = 32'hFF5FFDEF;  // JAL  x27, -12      BACKWARD -> [28], x27 = 128
        dut.imem_inst.memory[32] = 32'h016E0E13;  // ADDI x28, x28, 22  retires exactly once

        // ----------------------------------------------------------------
        // Case 3: JALR whose rs1 + imm is ODD (160 + 5 = 165). The target
        // must be 164, not 165. Link = pc + 4 = 140 + 4 = 144.
        // ----------------------------------------------------------------
        dut.imem_inst.memory[34] = 32'h0A000813;  // ADDI x16, x0, 160
        dut.imem_inst.memory[35] = 32'h005808E7;  // JALR x17, 5(x16)   -> (165 & ~1) = 164 = [41]
        dut.imem_inst.memory[36] = 32'h06300913;  // ADDI x18, x0, 99   wrong path
        dut.imem_inst.memory[37] = 32'h06300993;  // ADDI x19, x0, 99   wrong path
        dut.imem_inst.memory[41] = 32'h03F00E93;  // ADDI x29, x0, 63   JALR landing marker

        // ----------------------------------------------------------------
        // Case 5: false-stall exclusion. Each load below is immediately
        // followed by an instruction whose rs1 or rs2 BIT FIELD equals the
        // load's rd but is not a source operand:
        //   [43] LUI   x30, 0x00030 -> instr[19:15] = 6  = rd of [42]
        //   [45] JAL   x0,  +4      -> instr[24:20] = 4  = rd of [44]
        //   [47] AUIPC x4,  0x00018 -> instr[19:15] = 3  = rd of [46]
        //   [49] ADDI  x6,  x0, 3   -> instr[24:20] = 3  = rd of [48]
        //   [53] JALR  x0,  3(x16)  -> instr[24:20] = 3  = rd of [52]
        //   [59] LB    x3,  3(x0)   -> instr[24:20] = 3  = rd of [58]
        // That covers every decode arm in this implementation that leaves a
        // source field unused: the three opcodes with no source registers at
        // all (LUI / AUIPC / JAL) and all three that use rs1 only, so their
        // rs2 field is immediate bits (I-type ALU / JALR / LOAD).
        // None of these may raise load_use_hazard. dmem[1] holds 5 from [4],
        // so the loads return a non-zero value and are provably real.
        // ----------------------------------------------------------------
        dut.imem_inst.memory[42] = 32'h00402303;  // LW    x6, 4(x0)    x6 = 5
        dut.imem_inst.memory[43] = 32'h00030F37;  // LUI   x30, 0x00030
        dut.imem_inst.memory[44] = 32'h00402203;  // LW    x4, 4(x0)    x4 = 5
        dut.imem_inst.memory[45] = 32'h0040006F;  // JAL   x0, +4       -> [46]
        dut.imem_inst.memory[46] = 32'h00402183;  // LW    x3, 4(x0)    x3 = 5
        dut.imem_inst.memory[47] = 32'h00018217;  // AUIPC x4, 0x00018  x4 = 188 + 0x18000
        dut.imem_inst.memory[48] = 32'h00402183;  // LW    x3, 4(x0)    x3 = 5
        dut.imem_inst.memory[49] = 32'h00300313;  // ADDI  x6, x0, 3    x6 = 3
        // Give dmem[0] byte 3 a value distinct from dmem[1], so the LB below
        // is provably the instruction that produced x3's final value.
        dut.imem_inst.memory[50] = 32'h00D001A3;  // SB    x13, 3(x0)   dmem[0] byte3 = 13
        dut.imem_inst.memory[51] = 32'h0E500813;  // ADDI  x16, x0, 229 JALR base
        dut.imem_inst.memory[52] = 32'h00402183;  // LW    x3, 4(x0)    x3 = 5
        dut.imem_inst.memory[53] = 32'h00380067;  // JALR  x0, 3(x16)   -> (229+3) = 232 = [58]
        dut.imem_inst.memory[58] = 32'h00402183;  // LW    x3, 4(x0)    x3 = 5
        dut.imem_inst.memory[59] = 32'h00300183;  // LB    x3, 3(x0)    x3 = 13
        dut.imem_inst.memory[60] = 32'h04D00813;  // ADDI  x16, x0, 77  JALR-alias landing marker
        dut.imem_inst.memory[61] = 32'h0000006F;  // JAL   x0, 0        park
    end

    // ------------------------------------------------------------------
    // Stall accounting and false-stall detection (cases 3 and 5).
    //
    // This program contains exactly one genuine load-use dependency, the
    // LW x14 / ADD x15,x14,x1 pair at [5]/[6]. Every other load here is
    // followed by an instruction that only *looks* dependent. So the total
    // stall count is itself the false-stall proof: any extra event means
    // the hazard unit compared a bit field that is not a source operand.
    // ------------------------------------------------------------------
    localparam logic [6:0] OPC_LUI   = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC = 7'b0010111;
    localparam logic [6:0] OPC_JAL   = 7'b1101111;

    int stall_events         = 0;
    int stall_run_len        = 0;
    int false_stall_errors   = 0;
    int pc_misaligned_errors = 0;

    logic [31:0] jalr_odd_target = 32'hDEADDEAD;   // captured case-3 JALR target

    always @(posedge clk) begin
        if (reset) stall_run_len = 0;
        else begin
            // Case 3 invariant: the PC must never become odd.
            if (dut.pc_value[0] !== 1'b0) begin
                pc_misaligned_errors++;
                $display("FAIL @%0t: PC is not even (%h)", $time, dut.pc_value);
            end

            // Case 3: capture the resolved target of the odd-sum JALR at pc 140.
            if (dut.id_ex_valid === 1'b1 && dut.id_ex_jalr === 1'b1 &&
                dut.id_ex_pc === 32'd140)
                jalr_odd_target = dut.ex_jalr_target;

            // Case 5: a stall while IF/ID holds an instruction with no
            // source registers at all is definitionally a false stall.
            if (dut.load_use_hazard === 1'b1) begin
                stall_run_len++;
                if (stall_run_len == 1) begin
                    stall_events++;
                    if (dut.if_id_instruction[6:0] === OPC_LUI   ||
                        dut.if_id_instruction[6:0] === OPC_AUIPC ||
                        dut.if_id_instruction[6:0] === OPC_JAL) begin
                        false_stall_errors++;
                        $display("FAIL @%0t: false load-use stall - IF/ID holds %h, opcode %b has no source registers",
                                 $time, dut.if_id_instruction, dut.if_id_instruction[6:0]);
                    end
                end
            end
            else stall_run_len = 0;
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

    task automatic check_val(input logic [31:0] actual, input logic [31:0] expected, input string why);
        checks++;
        if (actual !== expected) begin
            errors++;
            $display("FAIL: %s = %h, expected %h", why, actual, expected);
        end
        else $display("PASS: %s = %h", why, expected);
    endtask

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

    task automatic check_dmem(input int idx, input logic [31:0] expected, input string why);
        checks++;
        if (dut.dmem_inst.memory[idx] !== expected) begin
            errors++;
            $display("FAIL: dmem[%0d] = %h, expected %h  (%s)",
                     idx, dut.dmem_inst.memory[idx], expected, why);
        end
        else begin
            $display("PASS: dmem[%0d] = %h  (%s)", idx, expected, why);
        end
    endtask

    initial begin
        reset = 1'b1;
        #12;
        reset = 1'b0;

        #2000;

        $display("==== JAL / placeholders / memory regression checks ====");

        // JAL
        check_reg(5,  32'd8,  "JAL link register = pc+4 (4+4)");
        check_reg(1,  32'd5,  "ADDI before JAL executed");
        check_reg(20, 32'd0,  "wrong-path instr after JAL flushed");
        check_reg(21, 32'd0,  "second wrong-path instr after JAL flushed");

        // SW/LW regression + load-use hazard
        check_dmem(1, 32'd5,  "SW x1,4(x0) wrote data memory");
        check_reg(14, 32'd5,  "LW x14,4(x0) read back stored value");
        check_reg(15, 32'd10, "ADD after LW (load-use hazard stall + forward)");

        // Newly implemented subword / U-type instructions
        check_reg(7,  32'h12345000, "LUI x7,0x12345 -> imm20 << 12");
        check_reg(8,  32'h00001020, "AUIPC x8,1 -> instruction PC 32 + 0x1000");
        check_reg(9,  32'd0,  "LB from zeroed dmem word reads 0");
        check_reg(10, 32'd0,  "LH from zeroed dmem word reads 0");
        check_reg(11, 32'd0,  "LBU from zeroed dmem word reads 0");
        check_reg(12, 32'd0,  "LHU from zeroed dmem word reads 0");
        check_dmem(2, 32'h00000005, "SB x1,8(x0) wrote only byte 0");
        check_dmem(3, 32'h00000005, "SH x1,12(x0) wrote only halfword 0");
        check_reg(13, 32'd13, "marker after subword/U-type block executed");

        // JALR
        check_reg(2,  32'd96, "ADDI x2,x0,96 executed");
        check_reg(31, 32'd72, "JALR link register = pc+4 (68+4)");
        check_reg(22, 32'd0,  "wrong-path instr after JALR flushed");
        check_reg(23, 32'd0,  "second wrong-path instr after JALR flushed");
        check_reg(24, 32'd55, "JALR landed at rs1+imm target");

        $display("==== case 2: backward JAL / negative J-type immediate ====");

        check_reg(25, 32'd41,  "backward JAL landed at pc-12 (negative J immediate)");
        check_reg(27, 32'd128, "backward JAL link register = pc+4 (124+4)");
        check_reg(26, 32'd0,   "instruction only reachable on a wrong path stayed unexecuted");
        check_reg(28, 32'd22,  "backward JAL shadow flushed: continuation retired once, not twice");

        $display("==== case 3: JALR clears the target LSB ====");

        check_val(jalr_odd_target, 32'd164, "JALR target for rs1+imm = 165");
        check_count(pc_misaligned_errors, 0, "cycles in which the PC was odd");
        check_reg(29, 32'd63,  "execution resumed at the masked target 164");
        check_reg(17, 32'd144, "JALR link register = pc+4 (140+4)");
        check_reg(18, 32'd0,   "wrong-path instr after odd-sum JALR flushed");
        check_reg(19, 32'd0,   "second wrong-path instr after odd-sum JALR flushed");

        $display("==== case 5: false-stall exclusion ====");

        check_count(stall_events, 1, "load-use stall events (only the LW/ADD pair is genuine)");
        check_count(false_stall_errors, 0, "stalls raised for LUI / AUIPC / JAL");
        check_reg(30, 32'h00030000, "LUI after an rs1-field-aliasing load");
        check_val(dut.regfile_inst.registers[4], 32'h000180BC, "AUIPC after an rs1-field-aliasing load (x4)");
        check_reg(6,  32'd3, "ADDI whose immediate occupies the rs2 field, after an aliasing load");
        check_reg(3,  32'd13, "LB whose immediate occupies the rs2 field, after an aliasing load");
        check_reg(16, 32'd77, "JALR whose immediate occupies the rs2 field executed and landed");

        $display("==== cpu jal/placeholder result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_JAL_TB: ALL PASS");
        else             $display("CPU_JAL_TB: FAILED");
        $finish;
    end

endmodule
