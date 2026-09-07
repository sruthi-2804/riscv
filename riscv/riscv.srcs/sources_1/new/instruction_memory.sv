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
memory[0] = 32'h00002083;   // lw   x1, 0(x0)
memory[1] = 32'h000081B3;   // add  x3, x1, x0
memory[2] = 32'h00100213;   // addi x4, x0, 1
end
      assign instruction = memory[address[9:2]];
endmodule
