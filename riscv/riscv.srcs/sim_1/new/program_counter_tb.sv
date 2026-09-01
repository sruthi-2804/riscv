`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.08.2026 15:36:05
// Design Name: 
// Module Name: program_counter_tb
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
module program_counter_tb;

    logic        clk;
    logic        reset;
    logic        branch_taken;
    logic [31:0] branch_imm;
    logic [31:0] pc;

    // Instantiate DUT
    program_counter dut (
        .clk(clk),
        .reset(reset),
        .branch_taken(branch_taken),
        .branch_imm(branch_imm),
        .pc(pc)
    );

    // Clock generation
    always #5 clk = ~clk;

    initial begin

        clk          = 0;
        reset        = 1;
        branch_taken = 0;
        branch_imm   = 0;

        // Reset PC to 0
        #10;
        reset = 0;

        // Normal execution:
        // PC should go 0 -> 4 -> 8
        #10;
        $display("PC = %0d", pc);

        #10;
        $display("PC = %0d", pc);

        // At PC = 8:
        // Take branch with offset +12
        // target = 8 + 12 = 20
        branch_taken = 1;
        branch_imm   = 32'd12;

        #10;
        $display("After branch, PC = %0d", pc);

        // Return to normal execution
        branch_taken = 0;

        #10;
        $display("Next PC = %0d", pc);

        #10;
        $finish;

    end

endmodule
