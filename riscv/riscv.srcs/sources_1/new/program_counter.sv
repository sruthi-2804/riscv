`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.08.2026 15:34:57
// Design Name: 
// Module Name: program_counter
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

module program_counter (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] next_pc,
    output logic [31:0] pc
);

always_ff @(posedge clk) begin
    if (reset)
        pc <= 32'b0;
    else
        pc <= next_pc;
end

endmodule