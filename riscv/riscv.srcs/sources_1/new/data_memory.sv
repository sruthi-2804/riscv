`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.08.2026 13:00:02
// Design Name: 
// Module Name: data_memory
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


module data_memory (
    input  logic        clk,
    input  logic        reset,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [31:0] address,
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);

    // 256 memory locations, each 32 bits wide
    logic [31:0] memory [0:255];

    integer i;
//write op
    always_ff @(posedge clk) begin

        if (reset) begin
            for (i = 0; i < 256; i = i + 1)
                memory[i] <= 32'b0;
        end

        else if (mem_write) begin
            memory[address[9:2]] <= write_data;
        end

    end
//read op
    always_comb begin

        if (mem_read)
            read_data = memory[address[9:2]];
        else
            read_data = 32'b0;

    end

endmodule
