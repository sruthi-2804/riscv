`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.08.2026 21:14:34
// Design Name: 
// Module Name: branch_tb
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




module branch_tb;

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [2:0]  branch_control;
    logic        branch_taken;

    branch dut (
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .branch_control(branch_control),
        .branch_taken(branch_taken)
    );

    initial begin

        // BEQ: 10 == 10 → branch
        rs1_data = 32'd10;
        rs2_data = 32'd10;
        branch_control = 3'b000;
        #10;

        if (branch_taken != 1'b1)
            $error("BEQ failed");

        $display("BEQ: branch_taken = %b", branch_taken);


        // BNE: 10 != 20 → branch
        rs1_data = 32'd10;
        rs2_data = 32'd20;
        branch_control = 3'b001;
        #10;

        if (branch_taken != 1'b1)
            $error("BNE failed");

        $display("BNE: branch_taken = %b", branch_taken);


        // BLT: -5 < 10 → branch
        rs1_data = -32'sd5;
        rs2_data = 32'd10;
        branch_control = 3'b100;
        #10;

        if (branch_taken != 1'b1)
            $error("BLT failed");

        $display("BLT: branch_taken = %b", branch_taken);


        // BGE: 20 >= 10 → branch
        rs1_data = 32'd20;
        rs2_data = 32'd10;
        branch_control = 3'b101;
        #10;

        if (branch_taken != 1'b1)
            $error("BGE failed");

        $display("BGE: branch_taken = %b", branch_taken);


        // BLTU: 5 < 10 → branch
        rs1_data = 32'd5;
        rs2_data = 32'd10;
        branch_control = 3'b110;
        #10;

        if (branch_taken != 1'b1)
            $error("BLTU failed");

        $display("BLTU: branch_taken = %b", branch_taken);


        // BGEU: 20 >= 10 → branch
        rs1_data = 32'd20;
        rs2_data = 32'd10;
        branch_control = 3'b111;
        #10;

        if (branch_taken != 1'b1)
            $error("BGEU failed");

        $display("BGEU: branch_taken = %b", branch_taken);

        $finish;

    end

endmodule
    