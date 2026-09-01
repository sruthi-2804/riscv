`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.08.2026 12:59:07
// Design Name: 
// Module Name: data_memory_tb
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

module data_memory_tb;

    logic        clk;
    logic        reset;
    logic        mem_read;
    logic        mem_write;
    logic [31:0] address;
    logic [31:0] write_data;
    logic [31:0] read_data;


    // Instantiate Data Memory
    data_memory dut (
        .clk(clk),
        .reset(reset),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .address(address),
        .write_data(write_data),
        .read_data(read_data)
    );


    // Clock generation
    always #5 clk = ~clk;


    initial begin

        // Initial values
        clk        = 0;
        reset      = 1;
        mem_read   = 0;
        mem_write  = 0;
        address    = 0;
        write_data = 0;


        // Reset memory
        #10;
        reset = 0;

        // TEST 1: Store 25 at address 8
   address    = 32'd8;
        write_data = 32'd25;
        mem_write  = 1;

        #10;

        mem_write = 0;

        // TEST 2: Load from address 8
        
        address  = 32'd8;
        mem_read = 1;

        #2;

        if (read_data == 32'd25)
            $display("PASS: Address 8 contains %0d", read_data);
        else
            $display("FAIL: Expected 25, got %0d", read_data);

        // TEST 3: Store 100 at address 12

        mem_read   = 0;
        address    = 32'd12;
        write_data = 32'd100;
        mem_write  = 1;

        #10;

        mem_write = 0;

        // TEST 4: Load from address 12
        address  = 32'd12;
        mem_read = 1;

        #2;

        if (read_data == 32'd100)
            $display("PASS: Address 12 contains %0d", read_data);
        else
            $display("FAIL: Expected 100, got %0d", read_data);

        // TEST 5: Check address 8 again

        address = 32'd8;

        #2;

        if (read_data == 32'd25)
            $display("PASS: Address 8 still contains %0d", read_data);
        else
            $display("FAIL: Expected 25, got %0d", read_data);


        $finish;

    end

endmodule