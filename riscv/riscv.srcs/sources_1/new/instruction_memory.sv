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
memory[0] = 32'h00500013; // addi x0, x0, 5
memory[1] = 32'h00000133; // add  x2, x0, x0
end
      assign instruction = memory[address[9:2]];
endmodule
