`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.08.2026 19:49:29
// Design Name: 
// Module Name: immediate_tb
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
module immediate_generator_tb;

    logic [31:0] instruction;
    logic [2:0]  imm_sel;
    logic [31:0] immediate;

    immediate_generator dut (
        .instruction(instruction),
        .imm_sel(imm_sel),
        .immediate(immediate)
    );

    localparam logic [2:0]
        IMM_I = 3'b000,
        IMM_S = 3'b001,
        IMM_B = 3'b010,
        IMM_U = 3'b011,
        IMM_J = 3'b100;

    task check_imm(
        input logic [31:0] instr,
        input logic [2:0]  sel,
        input logic [31:0] expected
    );
        begin
            instruction = instr;
            imm_sel     = sel;

            #10;

            if (immediate === expected)
                $display("PASS: immediate = %h", immediate);
            else
                $display("FAIL: expected = %h, got = %h",
                         expected, immediate);
        end
    endtask

    initial begin

        // Tests will go here

        $finish;
    end

endmodule