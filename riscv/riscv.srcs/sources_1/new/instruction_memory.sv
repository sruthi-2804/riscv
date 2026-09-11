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
memory[0]  = 32'h00500093;  // addi x1, x0, 5
memory[1]  = 32'h00300113;  // addi x2, x0, 3

memory[2]  = 32'h002081B3;  // add  x3, x1, x2      -> 8
memory[3]  = 32'h40218233;  // sub  x4, x3, x2      -> 5

memory[4]  = 32'h00402023;  // sw   x4, 0(x0)
memory[5]  = 32'h00002283;  // lw   x5, 0(x0)       -> 5

memory[6]  = 32'h00128333;  // add  x6, x5, x1      -> 10
                            // immediate load-use dependency

memory[7]  = 32'h00630463;  // beq  x6, x6, +8      -> TAKEN
memory[8]  = 32'h06300393;  // addi x7, x0, 99      -> MUST FLUSH
memory[9]  = 32'h00700393;  // addi x7, x0, 7       -> x7 = 7

memory[10] = 32'h0080046F;  // jal  x8, +8
                            // x8 = PC+4 = 0x2C

memory[11] = 32'h06300493;  // addi x9, x0, 99      -> MUST FLUSH
memory[12] = 32'h00900493;  // addi x9, x0, 9       -> x9 = 9
end
      assign instruction = memory[address[9:2]];
endmodule
