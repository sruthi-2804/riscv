`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.08.2026 13:39:00
// Design Name: 
// Module Name: riscv_cpu
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


module riscv_cpu (
    input logic clk,
    input logic reset
);

    // write back for load
    logic mem_to_reg;
    
    // PC / instruction signals
    logic [31:0] pc_value;
    logic [31:0] next_pc;
    logic [31:0] instruction;

    // Instruction fields
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

 // Control signals
logic       reg_write;
logic       alu_src;
logic       mem_read;
logic       mem_write;
logic       branch;
logic [3:0] alu_control;
logic [31:0] pc_plus_4;
logic [31:0] branch_target;
logic [31:0] jump_target;

logic branch_taken;
logic jump;
    
 //memory
 logic [31:0] mem_read_data;
    
 //reg file signals
logic [4:0] rs1;
logic [4:0] rs2;
logic [4:0] rd;

logic [31:0] read_data_1;
logic [31:0] read_data_2;
logic [31:0] write_data;

//imm gen wires
logic [31:0] immediate;
logic [2:0] imm_sel;
//alusrc mux
logic [31:0] alu_operand_b;
logic [31:0] alu_result;
logic zero;

// MEM/WB pipeline register signals (declared here so the WB mux and regfile ports below can use them)
logic [31:0] mem_wb_mem_read_data;
logic [31:0] mem_wb_alu_result;
logic [4:0]  mem_wb_rd;

logic        mem_wb_reg_write;
logic        mem_wb_mem_to_reg;

//pc 3 way mux
assign pc_plus_4 = pc_value + 32'd4;

assign branch_target = pc_value + immediate;

assign jump_target = pc_value + immediate;

always_comb begin
    if (mem_wb_mem_to_reg)
        write_data = mem_wb_mem_read_data;
    else
        write_data = mem_wb_alu_result;
end



// Extract fields from fetched instruction
assign opcode = instruction[6:0];
assign funct3 = instruction[14:12];
assign funct7 = instruction[31:25];



//pc
program_counter pc_inst (
    .clk(clk),
    .reset(reset),
    .next_pc(next_pc),
    .pc(pc_value)
);
always_comb begin
    if (jump)
        next_pc = jump_target;
    else if (branch_taken)
        next_pc = branch_target;
    else
        next_pc = pc_plus_4;
end

    // Instruction Memory
    instruction_memory imem_inst (
        .address(pc_value),
        .instruction(instruction)
    );
//implementing IF/ID reg
logic [31:0] if_id_pc;
logic [31:0] if_id_instruction;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        if_id_pc          <= 32'b0;
        if_id_instruction <= 32'b0;
    end
    else begin
        if_id_pc          <= pc_value;
        if_id_instruction <= instruction;
    end
end
//instruction belongs to the instruction being fetched right now. if_id_instruction belongs to the instruction currently sitting in ID.
assign rs1 = if_id_instruction[19:15];  
assign rs2 = if_id_instruction[24:20];  
assign rd  = if_id_instruction[11:7];   
    
 // ID/EX pipeline register - datapath
logic [31:0] id_ex_pc;

logic [4:0]  id_ex_rs1;
logic [4:0]  id_ex_rs2;
logic [4:0]  id_ex_rd;

logic [31:0] id_ex_rs1_data;
logic [31:0] id_ex_rs2_data;
logic [31:0] id_ex_immediate;

logic [2:0]  id_ex_funct3;

// ID/EX pipeline register - control
logic        id_ex_reg_write;
logic        id_ex_alu_src;
logic        id_ex_mem_read;
logic        id_ex_mem_write;
logic        id_ex_mem_to_reg;
logic        id_ex_branch;
logic        id_ex_jal;

logic [3:0]  id_ex_alu_control;


always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        id_ex_pc          <= 32'b0;

        id_ex_rs1         <= 5'b0;
        id_ex_rs2         <= 5'b0;
        id_ex_rd          <= 5'b0;

        id_ex_rs1_data    <= 32'b0;
        id_ex_rs2_data    <= 32'b0;
        id_ex_immediate   <= 32'b0;

        id_ex_funct3      <= 3'b0;

        id_ex_reg_write   <= 1'b0;
        id_ex_alu_src     <= 1'b0;
        id_ex_mem_read    <= 1'b0;
        id_ex_mem_write   <= 1'b0;
        id_ex_mem_to_reg  <= 1'b0;
        id_ex_branch      <= 1'b0;
        id_ex_jal         <= 1'b0;

        id_ex_alu_control <= 4'b0;
    end

    else begin
        id_ex_pc          <= if_id_pc;

        id_ex_rs1         <= rs1;
        id_ex_rs2         <= rs2;
        id_ex_rd          <= rd;

        id_ex_rs1_data    <= read_data_1;
        id_ex_rs2_data    <= read_data_2;
        id_ex_immediate   <= immediate;

        id_ex_funct3      <= if_id_instruction[14:12];

        id_ex_reg_write   <= reg_write;
        id_ex_alu_src     <= alu_src;
        id_ex_mem_read    <= mem_read;
        id_ex_mem_write   <= mem_write;
        id_ex_mem_to_reg  <= mem_to_reg;
        id_ex_branch      <= branch;
        id_ex_jal         <= jump;

        id_ex_alu_control <= alu_control;
    end
end

//implementing mux in EX stage
assign alu_operand_b =id_ex_alu_src ?id_ex_immediate: id_ex_rs2_data;


// EX/MEM pipeline register - datapath
logic [31:0] ex_mem_alu_result;
logic [31:0] ex_mem_rs2_data;
logic [4:0]  ex_mem_rd;

// EX/MEM control
logic        ex_mem_reg_write;
logic        ex_mem_mem_read;
logic        ex_mem_mem_write;
logic        ex_mem_mem_to_reg;

// Branch/jump information
logic [31:0] ex_branch_target;
logic        ex_branch_taken;
logic        ex_mem_jump;

assign ex_branch_target = id_ex_pc + id_ex_immediate;



 // Decoder / Control Unit
    control_unit control_inst (
   .opcode(if_id_instruction[6:0]),
.funct3(if_id_instruction[14:12]),
.funct7(if_id_instruction[31:25]),
     .jump(jump),
    .imm_sel(imm_sel),
    .reg_write(reg_write),
    .alu_src(alu_src),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .branch(branch),
    .mem_to_reg(mem_to_reg),
    .alu_control(alu_control)
);

//reg file
register_file regfile_inst (
    .clk(clk),
    .reset(reset),

    .read_addr_1(rs1),
    .read_addr_2(rs2),
    .write_addr(mem_wb_rd),
.write_data(write_data),
.write_enable(mem_wb_reg_write),
    .read_data_1(read_data_1),
    .read_data_2(read_data_2)
);

//imm gen
immediate_generator imm_gen_inst(
    .instruction(if_id_instruction),
    .imm_sel(imm_sel),
    .immediate(immediate)
);


//alu
alu alu_inst (
    .operand_a   (id_ex_rs1_data),
    .operand_b   (alu_operand_b),
    .alu_control (id_ex_alu_control),
    .result      (alu_result)
);
//data memory
data_memory dmem_inst (
    .clk(clk),
    .reset(reset),

    .mem_read(ex_mem_mem_read),
    .mem_write(ex_mem_mem_write),

    .address(ex_mem_alu_result),
    .write_data(ex_mem_rs2_data),

    .read_data(mem_read_data)
);

branch_unit branch_inst (
    .branch(id_ex_branch),
    .funct3(id_ex_funct3),
    .operand_a(id_ex_rs1_data),
    .operand_b(id_ex_rs2_data),
    .branch_taken(ex_branch_taken)
);

//EX/MEM
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        ex_mem_alu_result <= 32'b0;
        ex_mem_rs2_data   <= 32'b0;
        ex_mem_rd         <= 5'b0;

        ex_mem_reg_write  <= 1'b0; //write Register File
        ex_mem_mem_read   <= 1'b0; //read Data Memory
        ex_mem_mem_write  <= 1'b0; //write Data Memory
        ex_mem_mem_to_reg <= 1'b0; //choose memory vs ALU data for Register File write
        ex_mem_jump <= 1'b0; 
    end
    else begin
        ex_mem_alu_result <= alu_result;
        ex_mem_rs2_data   <= id_ex_rs2_data;
        ex_mem_rd         <= id_ex_rd;

        ex_mem_reg_write  <= id_ex_reg_write;
        ex_mem_mem_read   <= id_ex_mem_read;
        ex_mem_mem_write  <= id_ex_mem_write;
        ex_mem_mem_to_reg <= id_ex_mem_to_reg;

        ex_mem_jump       <= id_ex_jal;
    end
end
// MEM/WB pipeline register (signals declared near the top with the WB mux)
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        mem_wb_mem_read_data <= 32'b0;
        mem_wb_alu_result    <= 32'b0;
        mem_wb_rd            <= 5'b0;

        mem_wb_reg_write     <= 1'b0;
        mem_wb_mem_to_reg    <= 1'b0;
    end
    else begin
        mem_wb_mem_read_data <= mem_read_data;
        mem_wb_alu_result    <= ex_mem_alu_result;
        mem_wb_rd            <= ex_mem_rd;

        mem_wb_reg_write     <= ex_mem_reg_write;
        mem_wb_mem_to_reg    <= ex_mem_mem_to_reg;
    end
end


endmodule