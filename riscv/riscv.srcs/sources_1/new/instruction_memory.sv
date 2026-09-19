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
    integer i;
     
     //test instructions

initial begin
for (i = 0; i < 256; i = i + 1)
    memory[i] = 32'h00000013;   // ADDI x0, x0, 0

memory[0]  = 32'h00500093;   // ADDI x1,  x0, 5
memory[1]  = 32'h00300113;   // ADDI x2,  x0, 3
memory[2]  = 32'h00209463;   // BNE  x1,  x2, +8   taken
memory[3]  = 32'h06300A13;   // ADDI x20, x0, 99   flushed
memory[4]  = 32'h00109463;   // BNE  x1,  x1, +8   not taken
memory[5]  = 32'h01500A93;   // ADDI x21, x0, 21   executes

memory[6]  = 32'hFFF00413;   // ADDI x8,  x0, -1
memory[7]  = 32'h00100493;   // ADDI x9,  x0, 1
memory[8]  = 32'h00944463;   // BLT  x8,  x9, +8   signed taken
memory[9]  = 32'h06300B13;   // ADDI x22, x0, 99   flushed
memory[10] = 32'h00945463;   // BGE  x8,  x9, +8   signed not taken
memory[11] = 32'h01700B93;   // ADDI x23, x0, 23   executes

memory[12] = 32'h00946463;   // BLTU x8,  x9, +8   unsigned not taken
memory[13] = 32'h01800C13;   // ADDI x24, x0, 24   executes
memory[14] = 32'h00947463;   // BGEU x8,  x9, +8   unsigned taken
memory[15] = 32'h06300C93;   // ADDI x25, x0, 99   flushed

memory[16] = 32'h00700513;   // ADDI x10, x0, 7
memory[17] = 32'h009505B3;   // ADD  x11, x10, x9   x11 = 8
memory[18] = 32'h00A59463;   // BNE  x11, x10, +8   taken using forwarded x11
memory[19] = 32'h06300D13;   // ADDI x26, x0, 99   flushed
memory[20] = 32'h01B00D93;   // ADDI x27, x0, 27   executes

memory[21] = 32'h0084D463;   // BGE  x9,  x8, +8   signed taken with negative operand
memory[22] = 32'h06300E13;   // ADDI x28, x0, 99   flushed
memory[23] = 32'h01D00E93;   // ADDI x29, x0, 29   executes
end
      assign instruction = memory[address[9:2]];
endmodule
