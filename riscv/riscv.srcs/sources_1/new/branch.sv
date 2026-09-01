`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.08.2026 21:11:50
// Design Name: 
// Module Name: branch
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


module branch_unit (
    input  logic        branch,
    input  logic [2:0]  funct3,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,

    output logic        branch_taken
);

always_comb begin

    // Default: do not branch
    branch_taken = 1'b0;

    if (branch) begin

        case (funct3)

            3'b000: begin       // BEQ
                branch_taken = (operand_a == operand_b);
            end

            3'b001: begin       // BNE
                branch_taken = (operand_a != operand_b);
            end

            3'b100: begin       // BLT - signed
                branch_taken =
                    ($signed(operand_a) < $signed(operand_b));
            end

            3'b101: begin       // BGE - signed
                branch_taken =
                    ($signed(operand_a) >= $signed(operand_b));
            end

            3'b110: begin       // BLTU - unsigned
                branch_taken = (operand_a < operand_b);
            end

            3'b111: begin       // BGEU - unsigned
                branch_taken = (operand_a >= operand_b);
            end

            default: begin
                branch_taken = 1'b0;
            end

        endcase
    end
end

endmodule


