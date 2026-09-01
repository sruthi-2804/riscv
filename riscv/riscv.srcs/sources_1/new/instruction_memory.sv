`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.08.2026 11:41:30
// Design Name: 
// Module Name: instruction_memory
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


module instruction_memory(
input logic [31:0]address,
output logic [31:0]instruction
    );
    // creates memory space for 256 locations each wiht size 32 bits
    logic[31:0] memory[0:255];
     
     //test instructions

    initial begin
    memory[0]  = 32'h00500093;   // addi x1, x0, 5
    memory[1]  = 32'h00500113;   // addi x2, x0, 5

    memory[2]  = 32'h00208463;   // beq x1, x2, +8
    memory[3]  = 32'h06300193;   // skipped

    memory[4]  = 32'h00A00193;   // addi x3, x0, 10
    memory[5]  = 32'h00100213;   // addi x4, x0, 1

    memory[6]  = 32'h00408463;   // beq x1, x4, +8 (not taken)
    memory[7]  = 32'h01400293;   // addi x5, x0, 20

    memory[8]  = 32'h0080036F;   // jal x6, +8
    memory[9]  = 32'h06300393;   // skipped

    memory[10] = 32'h01E00393;   // addi x7, x0, 30
end

      assign instruction = memory[address[9:2]];
endmodule
