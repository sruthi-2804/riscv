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
memory[0] = 32'h00100093;   // ADDI x1, x0, 1
memory[1] = 32'h00100113;   // ADDI x2, x0, 1
memory[2] = 32'h00208663;   // BEQ  x1, x2, +12
memory[3] = 32'h06300193;   // ADDI x3, x0, 99  <- WRONG PATH
memory[4] = 32'h00302023;   // SW   x3, 0(x0)   <- WRONG PATH
memory[5] = 32'h00A00293;   // ADDI x5, x0, 10  <- TARGET
end
      assign instruction = memory[address[9:2]];
endmodule
