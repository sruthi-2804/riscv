`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.08.2026 08:06:13
// Design Name: 
// Module Name: reg_file
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


module register_file (

    input  logic        clk,
    input  logic        reset,

    input  logic [4:0]  read_addr_1,
    input  logic [4:0]  read_addr_2,

    input  logic [4:0]  write_addr,
    input  logic [31:0] write_data,
    input  logic        write_enable,

    output logic [31:0] read_data_1,
    output logic [31:0] read_data_2
);

logic [31:0] registers [0:31];

assign read_data_1 =
    (read_addr_1 == 5'd0) ?
    32'd0 :
    registers[read_addr_1];

assign read_data_2 =
    (read_addr_2 == 5'd0) ?
    32'd0 :
    registers[read_addr_2];

always_ff @(posedge clk)
begin
    if(reset)
    begin
        for(int i=0;i<32;i++)
            registers[i] <= 32'd0;
    end
    else if(write_enable && write_addr !=5'd0)
    begin
        registers[write_addr] <= write_data;
    end
end

endmodule
