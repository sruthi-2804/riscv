`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.08.2026 05:44:05
// Design Name: 
// Module Name: alu
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

module alu (
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [3:0]  alu_control,
    output logic [31:0] result,
    output logic        zero
);
    localparam logic [3:0]
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_AND  = 4'b0010,
        ALU_OR   = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SLL  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_SLT  = 4'b1000,
        ALU_SLTU = 4'b1001;


   

    always_comb begin

        result = 32'b0;

        case (alu_control)

            ALU_ADD:
                result = operand_a + operand_b;

            ALU_SUB:
                result = operand_a - operand_b;

            ALU_AND:
                result = operand_a & operand_b;

            ALU_OR:
                result = operand_a | operand_b;

            ALU_XOR:
                result = operand_a ^ operand_b;

            ALU_SLL:
                result = operand_a << operand_b[4:0];

            ALU_SRL:
                result = operand_a >> operand_b[4:0];

            ALU_SRA:
                result = $signed(operand_a) >>> operand_b[4:0];

            ALU_SLT:
                result = ($signed(operand_a) < $signed(operand_b))
                       ? 32'd1
                       : 32'd0;

            ALU_SLTU:
                result = (operand_a < operand_b)
                       ? 32'd1
                       : 32'd0;

            default:
                result = 32'b0;

        endcase

    end

    assign zero = (result == 32'b0);

endmodule

      