`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.08.2026 09:52:03
// Design Name: 
// Module Name: alu_tb
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
`timescale 1ns/1ps

module alu_tb;

    // Testbench signals

    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [3:0]  alu_control;

    logic [31:0] result;
    logic        zero;

    // ALU operation encoding
    // Must match the encoding used inside the ALU

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

    // Device Under Test

    alu dut (
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .alu_control (alu_control),
        .result      (result),
        .zero        (zero)
    );

    // Reusable test task

    task automatic check_alu (
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [3:0]  test_control,
        input logic [31:0] expected_result,
        input logic        expected_zero
    );

        begin
            operand_a   = test_a;
            operand_b   = test_b;
            alu_control = test_control;

            // Allow combinational logic to settle
            #1;

            if ((result !== expected_result) ||
                (zero   !== expected_zero)) begin

                $error(
                    "FAILED: A=%h B=%h control=%b result=%h expected=%h zero=%b expected_zero=%b",
                    operand_a,
                    operand_b,
                    alu_control,
                    result,
                    expected_result,
                    zero,
                    expected_zero
                );

            end
            else begin

                $display(
                    "PASSED: A=%h B=%h control=%b result=%h zero=%b",
                    operand_a,
                    operand_b,
                    alu_control,
                    result,
                    zero
                );

            end
        end

    endtask


    // Test sequence


    initial begin

        $display("==============================================");
        $display("Starting ALU Testbench");
        $display("==============================================");

        // Initial values

        operand_a   = 32'b0;
        operand_b   = 32'b0;
        alu_control = 4'b0;

        #1;


        // ADD tests


        check_alu(
            32'd10,
            32'd20,
            ALU_ADD,
            32'd30,
            1'b0
        );

        check_alu(
            32'd0,
            32'd0,
            ALU_ADD,
            32'd0,
            1'b1
        );

        check_alu(
            32'hFFFF_FFFF,
            32'd1,
            ALU_ADD,
            32'h0000_0000,
            1'b1
        );


        // SUB tests


        check_alu(
            32'd20,
            32'd10,
            ALU_SUB,
            32'd10,
            1'b0
        );

        check_alu(
            32'd10,
            32'd10,
            ALU_SUB,
            32'd0,
            1'b1
        );

        check_alu(
            32'd5,
            32'd10,
            ALU_SUB,
            32'hFFFF_FFFB,
            1'b0
        );


        // AND tests


        check_alu(
            32'hFFFF_0000,
            32'h0F0F_0F0F,
            ALU_AND,
            32'h0F0F_0000,
            1'b0
        );

        check_alu(
            32'hAAAA_AAAA,
            32'h5555_5555,
            ALU_AND,
            32'h0000_0000,
            1'b1
        );


        // OR tests


        check_alu(
            32'hFFFF_0000,
            32'h0000_FFFF,
            ALU_OR,
            32'hFFFF_FFFF,
            1'b0
        );

        check_alu(
            32'h0000_0000,
            32'h0000_0000,
            ALU_OR,
            32'h0000_0000,
            1'b1
        );


        // XOR tests


        check_alu(
            32'hAAAA_AAAA,
            32'h5555_5555,
            ALU_XOR,
            32'hFFFF_FFFF,
            1'b0
        );

        check_alu(
            32'h1234_5678,
            32'h1234_5678,
            ALU_XOR,
            32'h0000_0000,
            1'b1
        );

        check_alu(
            32'hFFFF_0000,
            32'h0F0F_0F0F,
            ALU_XOR,
            32'hF0F0_0F0F,
            1'b0
        );


        // SLL tests
        // Shift amount comes from operand_b[4:0]


        check_alu(
            32'h0000_0001,
            32'd4,
            ALU_SLL,
            32'h0000_0010,
            1'b0
        );

        check_alu(
            32'h0000_0001,
            32'd31,
            ALU_SLL,
            32'h8000_0000,
            1'b0
        );

        check_alu(
            32'h0000_0000,
            32'd10,
            ALU_SLL,
            32'h0000_0000,
            1'b1
        );

        check_alu(
            32'h0000_0001,
            32'd32,
            ALU_SLL,
            32'h0000_0001,
            1'b0
        );


        // SRL tests
        // Logical right shift inserts zeros from the left


        check_alu(
            32'h8000_0000,
            32'd1,
            ALU_SRL,
            32'h4000_0000,
            1'b0
        );

        check_alu(
            32'hFFFF_FFFF,
            32'd4,
            ALU_SRL,
            32'h0FFF_FFFF,
            1'b0
        );

        check_alu(
            32'h0000_0001,
            32'd1,
            ALU_SRL,
            32'h0000_0000,
            1'b1
        );


        // SRA tests
        // Arithmetic right shift preserves the sign bit


        check_alu(
            32'h8000_0000,
            32'd1,
            ALU_SRA,
            32'hC000_0000,
            1'b0
        );

        check_alu(
            32'hFFFF_FFF8,
            32'd1,
            ALU_SRA,
            32'hFFFF_FFFC,
            1'b0
        );

        check_alu(
            32'h0000_0008,
            32'd2,
            ALU_SRA,
            32'h0000_0002,
            1'b0
        );

        check_alu(
            32'h0000_0001,
            32'd1,
            ALU_SRA,
            32'h0000_0000,
            1'b1
        );


        // SLT tests
        // Signed comparison


        check_alu(
            32'hFFFF_FFFB,
            32'd2,
            ALU_SLT,
            32'd1,
            1'b0
        );

        check_alu(
            32'd5,
            32'd2,
            ALU_SLT,
            32'd0,
            1'b1
        );

        check_alu(
            32'hFFFF_FFFF,
            32'h0000_0001,
            ALU_SLT,
            32'd1,
            1'b0
        );

        check_alu(
            32'd10,
            32'd10,
            ALU_SLT,
            32'd0,
            1'b1
        );


        // SLTU tests
        // Unsigned comparison


        check_alu(
            32'hFFFF_FFFF,
            32'd1,
            ALU_SLTU,
            32'd0,
            1'b1
        );

        check_alu(
            32'd1,
            32'hFFFF_FFFF,
            ALU_SLTU,
            32'd1,
            1'b0
        );

        check_alu(
            32'd5,
            32'd10,
            ALU_SLTU,
            32'd1,
            1'b0
        );

        check_alu(
            32'd10,
            32'd10,
            ALU_SLTU,
            32'd0,
            1'b1
        );


        // Invalid ALU control test


        check_alu(
            32'h1234_5678,
            32'h8765_4321,
            4'b1111,
            32'h0000_0000,
            1'b1
        );


        $display("==============================================");
        $display("ALU Testbench Completed");
        $display("==============================================");

        $finish;

    end

endmodule