`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.08.2026 09:21:59
// Design Name: 
// Module Name: register_file_tb
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


module register_file_tb;

    logic clk;
    logic reset;

    logic [4:0]  read_addr_1;
    logic [4:0]  read_addr_2;
     logic [4:0]  write_addr;
     logic [31:0] write_data;
     logic write_enable;

     logic [31:0] read_data_1;
    logic [31:0] read_data_2;
    
    register_file dut( .clk(clk), .reset(reset), .read_addr_1(read_addr_1), .read_addr_2(read_addr_2), .write_addr(write_addr), .write_data(write_data), .write_enable(write_enable), .read_data_1(read_data_1), .read_data_2(read_data_2));
    always #5 clk=~clk;
    initial begin
    clk=0;
    reset=1;
    read_addr_1=0;
    read_addr_2=0;
    write_addr=0;
    write_data=0;
    write_enable=0;
    
    #10;
    
    // write x5=100
    reset=0;
     write_enable = 1;
    write_addr = 5;
    write_data = 100;

    #10;

    write_enable = 0;

    // to read x5
    read_addr_1 = 5;

    #1;
    if(read_data_1 == 100)
        $display("PASS : x5 = 100");
    else
        $display("FAIL : x5 incorrect");
        
// testing x0
    write_enable = 1;
    write_addr = 0;
    write_data = 200;

    #10;

    write_enable = 0;

    read_addr_1 = 0;

    #1;

    if(read_data_1 == 0)
        $display("PASS : x0 protected");
    else
        $display("FAIL : x0 modified");

    $finish;
    
    
  end  
endmodule
