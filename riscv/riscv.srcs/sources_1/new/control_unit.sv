`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.08.2026 09:02:38
// Design Name: 
// Module Name: control_unit
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

`timescale 1ns / 1ps

module control_unit (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,

    output logic reg_write,
    output logic alu_src,
    output logic mem_read,
    output logic mem_write,
    output logic branch,
    output logic jump,
    output logic [2:0] imm_sel,
    output logic mem_to_reg,
    output logic [3:0] alu_control
);

    // ALU control encodings
    localparam logic [3:0]
        ALU_ADD = 4'b0000,
        ALU_SUB = 4'b0001,
        ALU_AND = 4'b0010,
        ALU_OR  = 4'b0011;

    // Immediate type encodings
    localparam logic [2:0]
        IMM_I = 3'b000,
        IMM_S = 3'b001,
        IMM_B = 3'b010,
        IMM_U = 3'b011,
        IMM_J = 3'b100;

    always_comb begin

        // Default control values
        mem_to_reg = 1'b0;
        jump = 1'b0;
        reg_write   = 1'b0;
        alu_src     = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        branch      = 1'b0;
        alu_control = ALU_ADD;
        imm_sel     = IMM_I;

        case (opcode)

            // R-type: ADD, SUB, AND, OR
            7'b0110011: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;

                case (funct3)

                    3'b000: begin
                        if (funct7 == 7'b0100000)
                            alu_control = ALU_SUB;
                        else
                            alu_control = ALU_ADD;
                    end

                    3'b111:
                        alu_control = ALU_AND;

                    3'b110:
                        alu_control = ALU_OR;

                    default:
                        alu_control = ALU_ADD;

                endcase
            end
  // I-type arithmetic: ADDI
     7'b0010011: begin
     reg_write   = 1'b1;
     alu_src     = 1'b1;
     imm_sel     = IMM_I;
     alu_control = ALU_ADD;
     end
     // JAL
7'b1101111: begin   
    reg_write = 1'b1;
    jump      = 1'b1;
end

  // Load: LW
  7'b0000011: begin
  reg_write   = 1'b1;
  alu_src     = 1'b1;
  mem_read    = 1'b1;
  mem_write   = 1'b0;
  mem_to_reg  = 1'b1;
  alu_control = ALU_ADD;
  imm_sel     = IMM_I;
end

 // Store: SW
   7'b0100011: begin
   reg_write   = 1'b0;
   alu_src     = 1'b1;
   mem_read    = 1'b0;
   mem_write   = 1'b1;
  alu_control = ALU_ADD;
  imm_sel= IMM_S;
    end
  // Branch
     7'b1100011: begin
    reg_write   = 1'b0;
    alu_src     = 1'b0;
    mem_read    = 1'b0;
    mem_write   = 1'b0;
    branch      = 1'b1;
    alu_control = ALU_SUB;
    imm_sel     = IMM_B;
    end


   default: begin
   reg_write   = 1'b0;
   alu_src     = 1'b0;
   mem_read    = 1'b0;
   mem_write   = 1'b0;
   branch      = 1'b0;
   alu_control = ALU_ADD;
  imm_sel     = IMM_I;
  end

        endcase
    end

endmodule