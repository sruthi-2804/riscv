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
    output logic jalr,
    output logic reg_write,
    output logic alu_src,
    output logic mem_read,
    output logic mem_write,
    output logic branch,
    output logic jump,
    output logic [2:0] imm_sel,
    output logic mem_to_reg,
    output logic [1:0] mem_size,
    output logic load_unsigned,
    output logic [3:0] alu_control,
    output logic [1:0] alu_a_sel
);

    // ALU control encodings
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
    
    // Immediate type encodings
    localparam logic [2:0]
        IMM_I = 3'b000,
        IMM_S = 3'b001,
        IMM_B = 3'b010,
        IMM_U = 3'b011,
        IMM_J = 3'b100;
        
  localparam logic [1:0]
    MEM_BYTE = 2'b00,
    MEM_HALF = 2'b01,
    MEM_WORD = 2'b10;
    
    //lui/auipc
    localparam logic [1:0]
    ALU_A_RS1  = 2'b00,
    ALU_A_PC   = 2'b01,
    ALU_A_ZERO = 2'b10;
    
    

    always_comb begin

        // Default control values
        mem_to_reg = 1'b0;
        jump = 1'b0;
        jalr        = 1'b0;
        reg_write   = 1'b0;
        alu_src     = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        branch      = 1'b0;
        alu_control = ALU_ADD;
        imm_sel     = IMM_I;
        alu_a_sel = ALU_A_RS1;
        mem_size      = MEM_WORD;
        load_unsigned = 1'b0;
        
        case (opcode)

 // R-type integer ALU instructions
7'b0110011: begin
    alu_src = 1'b0;

    case (funct3)

        3'b000: begin
            if (funct7 == 7'b0100000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SUB;
            end
            else if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_ADD;
            end
        end

        3'b001: begin
            if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SLL;
            end
        end

        3'b010: begin
            if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SLT;
            end
        end

        3'b011: begin
            if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SLTU;
            end
        end

        3'b100: begin
            if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_XOR;
            end
        end

        3'b101: begin
            if (funct7 == 7'b0100000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SRA;
            end
            else if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SRL;
            end
        end

        3'b110: begin
            if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_OR;
            end
        end

        3'b111: begin
            if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_AND;
            end
        end

        default: begin
            reg_write = 1'b0;
        end

    endcase
end
// U-type
7'b0110111: begin       // LUI
    reg_write   = 1'b1;
    alu_src     = 1'b1;
    imm_sel     = IMM_U;
    alu_control = ALU_ADD;
    alu_a_sel   = ALU_A_ZERO;
end

7'b0010111: begin       // AUIPC
    reg_write   = 1'b1;
    alu_src     = 1'b1;
    imm_sel     = IMM_U;
    alu_control = ALU_ADD;
    alu_a_sel   = ALU_A_PC;
end

// I-type arithmetic/logical/shift instructions
7'b0010011: begin
    alu_src   = 1'b1;
    imm_sel   = IMM_I;

    case (funct3)

        3'b000: begin
            reg_write   = 1'b1;
            alu_control = ALU_ADD;   // ADDI
        end

        3'b001: begin               // SLLI: only funct7 = 0000000 is legal
            if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SLL;
            end
        end

        3'b010: begin
            reg_write   = 1'b1;
            alu_control = ALU_SLT;   // SLTI
        end

        3'b011: begin
            reg_write   = 1'b1;
            alu_control = ALU_SLTU;  // SLTIU
        end

        3'b100: begin
            reg_write   = 1'b1;
            alu_control = ALU_XOR;   // XORI
        end

        3'b101: begin               // SRLI/SRAI: only 0000000 / 0100000 legal
            if (funct7 == 7'b0100000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SRA;   // SRAI
            end
            else if (funct7 == 7'b0000000) begin
                reg_write   = 1'b1;
                alu_control = ALU_SRL;   // SRLI
            end
        end

        3'b110: begin
            reg_write   = 1'b1;
            alu_control = ALU_OR;    // ORI
        end

        3'b111: begin
            reg_write   = 1'b1;
            alu_control = ALU_AND;   // ANDI
        end

        default: begin
            reg_write = 1'b0;
        end

    endcase
end
     // JAL
7'b1101111: begin   
    reg_write = 1'b1;
    jump      = 1'b1;
    imm_sel   = IMM_J;
end

7'b1100111: begin       // JALR (only funct3 = 000 is a valid encoding)
    if (funct3 == 3'b000) begin
        jalr        = 1'b1;
        reg_write   = 1'b1;
        alu_src     = 1'b1;
        imm_sel     = IMM_I;
        alu_control = ALU_ADD;
    end
end

  // Loads: LB/LH/LW/LBU/LHU. mem_size and load_unsigned drive the
  // byte-lane selection and sign/zero extension in the MEM stage.
  7'b0000011: begin
  case (funct3)

    3'b000: begin   // LB
        mem_read       = 1'b1;
        reg_write      = 1'b1;
        mem_to_reg     = 1'b1;
        alu_src        = 1'b1;
        imm_sel        = IMM_I;

        mem_size       = MEM_BYTE;
        load_unsigned  = 1'b0;
    end

    3'b001: begin   // LH
        mem_read       = 1'b1;
        reg_write      = 1'b1;
        mem_to_reg     = 1'b1;
        alu_src        = 1'b1;
        imm_sel        = IMM_I;

        mem_size       = MEM_HALF;
        load_unsigned  = 1'b0;
    end

    3'b010: begin   // LW
        mem_read       = 1'b1;
        reg_write      = 1'b1;
        mem_to_reg     = 1'b1;
        alu_src        = 1'b1;
        imm_sel        = IMM_I;

        mem_size       = MEM_WORD;
        load_unsigned  = 1'b0;
    end

    3'b100: begin   // LBU
        mem_read       = 1'b1;
        reg_write      = 1'b1;
        mem_to_reg     = 1'b1;
        alu_src        = 1'b1;
        imm_sel        = IMM_I;

        mem_size       = MEM_BYTE;
        load_unsigned  = 1'b1;
    end

    3'b101: begin   // LHU
        mem_read       = 1'b1;
        reg_write      = 1'b1;
        mem_to_reg     = 1'b1;
        alu_src        = 1'b1;
        imm_sel        = IMM_I;

        mem_size       = MEM_HALF;
        load_unsigned  = 1'b1;
    end

    default: begin
   mem_size      = MEM_WORD;
  load_unsigned = 1'b0;
    end

endcase
end
 // Stores: SB/SH/SW. mem_size selects the byte-enable pattern and
 // store-data lane alignment in the MEM stage.
   7'b0100011: begin
   case (funct3)

    3'b000: begin   // SB
        mem_write = 1'b1;
        alu_src   = 1'b1;
        imm_sel   = IMM_S;
        mem_size  = MEM_BYTE;
    end

    3'b001: begin   // SH
        mem_write = 1'b1;
        alu_src   = 1'b1;
        imm_sel   = IMM_S;
        mem_size  = MEM_HALF;
    end

    3'b010: begin   // SW
        mem_write = 1'b1;
        alu_src   = 1'b1;
        imm_sel   = IMM_S;
        mem_size  = MEM_WORD;
    end

    default: begin
        // safe defaults
    end

endcase
    end
  // Branch
     7'b1100011: begin
    case (funct3)
        3'b000,
        3'b001,
        3'b100,
        3'b101,
        3'b110,
        3'b111: begin
            reg_write   = 1'b0;
            alu_src     = 1'b0;
            mem_read    = 1'b0;
            mem_write   = 1'b0;
            branch      = 1'b1;
            alu_control = ALU_SUB;
            imm_sel     = IMM_B;
        end

        default: begin
            branch = 1'b0;
        end
    endcase
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
