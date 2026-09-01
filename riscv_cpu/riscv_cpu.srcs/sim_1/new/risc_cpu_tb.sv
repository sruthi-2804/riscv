`timescale 1ns / 1ps
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

    riscv_cpu dut (
        .clk(clk),
        .reset(reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        reset = 1'b1;

        #12;
        reset = 1'b0;

        #100;

        $finish;
    end

    initial begin
        $monitor(
            "time=%0t PC=%0d instruction=%h next_pc=%0d branch=%b branch_taken=%b jump=%b rd=%0d reg_write=%b write_data=%0d",
            $time,
            dut.pc_value,
            dut.instruction,
            dut.next_pc,
            dut.branch,
            dut.branch_taken,
            dut.jump,
            dut.rd,
            dut.reg_write,
            dut.write_data
        );
    end

endmodule