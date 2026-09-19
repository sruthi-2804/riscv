`timescale 1ns / 1ps
// Full-CPU testbench: JAL/JALR, SW/LW regression, load-use hazard, plus basic
// checks of the now-implemented LUI/AUIPC/LB/LH/LBU/LHU/SB/SH instructions.
// (Expectations updated from the old "placeholder does nothing" behavior.)
// The test program is loaded into the existing instruction memory hierarchically
// from this testbench - no project source file is modified.

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

        #1000;

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

        $display("==== cpu jal/placeholder result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CPU_JAL_TB: ALL PASS");
        else             $display("CPU_JAL_TB: FAILED");
        $finish;
    end

endmodule
