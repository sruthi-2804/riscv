`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.08.2026 09:03:07
// Design Name: 
// Module Name: control_unit_tb
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


module control_unit_tb;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic       reg_write;
    logic       alu_src;
    logic       mem_read;
    logic       mem_write;
    logic       branch;
    logic [3:0] alu_control;


    
    localparam logic [3:0]
        ALU_ADD = 4'b0000,
        ALU_SUB = 4'b0001,
        ALU_AND = 4'b0010,
        ALU_OR  = 4'b0011;



    control_unit dut (
        .opcode      (opcode),
        .funct3      (funct3),
        .funct7      (funct7),

        .reg_write   (reg_write),
        .alu_src     (alu_src),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .branch      (branch),
        .alu_control (alu_control)
    );


    initial begin

        // Test 1: ADD
        
        opcode = 7'b0110011;
        funct3 = 3'b000;
        funct7 = 7'b0000000;

        #10;

        $display("ADD:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);

        // Test 2: SUB
        opcode = 7'b0110011;
        funct3 = 3'b000;
        funct7 = 7'b0100000;

        #10;

        $display("SUB:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);

        // Test 3: AND
        opcode = 7'b0110011;
        funct3 = 3'b111;
        funct7 = 7'b0000000;

        #10;

        $display("AND:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);

        // Test 4: OR

        opcode = 7'b0110011;
        funct3 = 3'b110;
        funct7 = 7'b0000000;

        #10;

        $display("OR:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);


        // Test 5: ADDI
 

        opcode = 7'b0010011;
        funct3 = 3'b000;
        funct7 = 7'b0000000;

        #10;

        $display("ADDI:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);

        // Test 6: LW


        opcode = 7'b0000011;
        funct3 = 3'b010;
        funct7 = 7'b0000000;

        #10;

        $display("LW:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);

        // Test 7: SW
        
        opcode = 7'b0100011;
        funct3 = 3'b010;
        funct7 = 7'b0000000;

        #10;

        $display("SW:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);

        // Test 8: BEQ
        
        opcode = 7'b1100011;
        funct3 = 3'b000;
        funct7 = 7'b0000000;

        #10;

        $display("BEQ:");
        $display("reg_write=%b alu_src=%b mem_read=%b mem_write=%b branch=%b alu_control=%b",
                 reg_write, alu_src, mem_read, mem_write, branch, alu_control);
        $finish;

    end

endmodule