`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.08.2026 19:48:23
// Design Name: 
// Module Name: immediate
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
module immediate_generator (
    input  logic [31:0] instruction,
    input  logic [2:0]  imm_sel,
    output logic [31:0] immediate
);
localparam logic [2:0]
    IMM_I = 3'b000,
    IMM_S = 3'b001,
    IMM_B = 3'b010,
    IMM_U = 3'b011,
    IMM_J = 3'b100;
always_comb begin
    immediate = 32'b0;

    case (imm_sel)

        IMM_I: begin
            immediate = {{20{instruction[31]}},
                         instruction[31:20]};
        end

        IMM_S: begin
            immediate = {{20{instruction[31]}},
                         instruction[31:25],
                         instruction[11:7]};
        end

        IMM_B: begin
            immediate = {{19{instruction[31]}},
                         instruction[31],
                         instruction[7],
                         instruction[30:25],
                         instruction[11:8],
                         1'b0};
        end

        IMM_U: begin
            immediate = {instruction[31:12],
                         12'b0};
        end

        IMM_J: begin
            immediate = {{11{instruction[31]}},
                         instruction[31],
                         instruction[19:12],
                         instruction[20],
                         instruction[30:21],
                         1'b0};
        end

        default: begin
            immediate = 32'b0;
        end

    endcase
end

endmodule