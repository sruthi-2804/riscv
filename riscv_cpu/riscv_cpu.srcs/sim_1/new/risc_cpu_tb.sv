//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.08.2026 15:24:28
// Design Name: 
// Module Name: risc_cpu_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module riscv_cpu_tb;

    logic clk;
    logic reset;


    // ============================================================
    // DUT
    // ============================================================

    riscv_cpu dut (
        .clk   (clk),
        .reset (reset)
    );


    // ============================================================
    // CLOCK GENERATION
    // 10 ns period
    // ============================================================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end


    // ============================================================
    // RESET + SIMULATION CONTROL
    // ============================================================

    initial begin

        reset = 1'b1;

        #12;
        reset = 1'b0;

        // Enough time for instructions to cross all 5 stages
        #150;

        $finish;
    end


    // ============================================================
    // PIPELINE MONITOR
    // ============================================================

    initial begin

        $monitor(
            "time=%0t | PC=%h instr=%h nextPC=%h | IFID_instr=%h | IDEX_rd=%0d imm=%h | ALU=%h | EXMEM_ALU=%h EXMEM_rd=%0d MR=%b MW=%b | MEM_data=%h | MEMWB_ALU=%h MEMWB_MEM=%h MEMWB_rd=%0d RegW=%b M2R=%b | WB_data=%h | branch_taken=%b jump=%b",

            $time,

            dut.pc_value,
            dut.instruction,
            dut.next_pc,

            dut.if_id_instruction,

            dut.id_ex_rd,
            dut.id_ex_immediate,

            dut.alu_result,

            dut.ex_mem_alu_result,
            dut.ex_mem_rd,
            dut.ex_mem_mem_read,
            dut.ex_mem_mem_write,

            dut.mem_read_data,

            dut.mem_wb_alu_result,
            dut.mem_wb_mem_read_data,
            dut.mem_wb_rd,
            dut.mem_wb_reg_write,
            dut.mem_wb_mem_to_reg,

            dut.write_data,

            dut.ex_branch_taken,
            dut.id_ex_jal
        );

    end


endmodule

