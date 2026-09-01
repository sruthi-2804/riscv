`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.08.2026 11:49:34
// Design Name: 
// Module Name: instrcution_memory_tb
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


module instruction_memory_tb;

    logic [31:0] address;
    logic [31:0] instruction;

    instruction_memory dut (
        .address(address),
        .instruction(instruction)
    );
    task check_instruction(
        input logic [31:0] test_address,
        input logic [31:0] expected_instruction
    );
    begin
            address = test_address;
            #1;

            if (instruction === expected_instruction)
                $display(
                    "PASS: address=%h instruction=%h",
                    address,
                    instruction
                );
            else
                $display(
                    "FAIL: address=%h expected=%h got=%h",
                    address,
                    expected_instruction,
                    instruction
                );
                end
                endtask
                initial begin

        check_instruction(
            32'h00000000,
            32'h00500093
        );

        check_instruction(
            32'h00000004,
            32'h00A00113
        );

        check_instruction(
            32'h00000008,
            32'h002081B3
        );

        check_instruction(
            32'h0000000C,
            32'h40118233
        );

        $finish;

    end

endmodule
