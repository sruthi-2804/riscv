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

// valid bits
logic if_id_valid;
logic id_ex_valid;
logic ex_mem_valid;
logic mem_wb_valid;

    // ============================================================
    // IF STAGE SIGNALS
    // ============================================================

    logic [31:0] pc_value;
    logic [31:0] next_pc;
    logic [31:0] pc_plus_4;
    logic [31:0] instruction;


    // ============================================================
    // IF/ID PIPELINE REGISTER
    // ============================================================

    logic [31:0] if_id_pc;
    logic [31:0] if_id_instruction;


    // ============================================================
    // ID STAGE SIGNALS
    // ============================================================

    // Register addresses decoded from IF/ID instruction
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;

    // Register file outputs
    logic [31:0] read_data_1;
    logic [31:0] read_data_2;

    // Immediate generator
    logic [31:0] immediate;
    logic [2:0]  imm_sel;

    // Decoder control outputs
    logic       reg_write;
    logic       alu_src;
    logic       mem_read;
    logic       mem_write;
    logic       mem_to_reg;
    logic       branch;
    logic       jump;
    logic [3:0] alu_control;


    // ============================================================
    // ID/EX PIPELINE REGISTER
    // ============================================================

    // Datapath
    logic [31:0] id_ex_pc;

    logic [4:0]  id_ex_rs1;
    logic [4:0]  id_ex_rs2;
    logic [4:0]  id_ex_rd;

    logic [31:0] id_ex_rs1_data;
    logic [31:0] id_ex_rs2_data;
    logic [31:0] id_ex_immediate;

    logic [2:0]  id_ex_funct3;

    // Control
    logic        id_ex_reg_write;
    logic        id_ex_alu_src;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic        id_ex_mem_to_reg;
    logic        id_ex_branch;
    logic        id_ex_jal;

    logic [3:0]  id_ex_alu_control;


    // ============================================================
    // EX STAGE SIGNALS
    // ============================================================

    logic [31:0] alu_operand_b;
    logic [31:0] alu_result;

    logic [31:0] ex_branch_target;
    logic [31:0] ex_jump_target;
    logic        ex_branch_taken;

    logic [31:0] ex_pc_plus_4;


    // ============================================================
    // EX/MEM PIPELINE REGISTER
    // ============================================================

    // Datapath
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_rs2_data;
    logic [31:0] ex_mem_pc_plus_4;
    logic [4:0]  ex_mem_rd;

    // MEM/WB control information
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic        ex_mem_mem_to_reg;
    logic        ex_mem_jump;


    // ============================================================
    // MEM STAGE SIGNALS
    // ============================================================

    logic [31:0] mem_read_data;


    // ============================================================
    // MEM/WB PIPELINE REGISTER
    // ============================================================

    logic [31:0] mem_wb_mem_read_data;
    logic [31:0] mem_wb_alu_result;
    logic [31:0] mem_wb_pc_plus_4;
    logic [4:0]  mem_wb_rd;

    logic        mem_wb_reg_write;
    logic        mem_wb_mem_to_reg;
    logic        mem_wb_jump;


    // ============================================================
    // WB STAGE SIGNALS
    // ============================================================

    logic [31:0] write_data;


    // ============================================================
    // IF STAGE
    // ============================================================

    assign pc_plus_4 = pc_value + 32'd4;


    program_counter pc_inst (
        .clk     (clk),
        .reset   (reset),
        .next_pc (next_pc),
        .pc      (pc_value)
    );


    instruction_memory imem_inst (
        .address     (pc_value),
        .instruction (instruction)
    );


    // ------------------------------------------------------------
    // Next-PC selection
    //
    // Branch and JAL are resolved in EX, therefore next_pc must use
    // EX-stage branch/jump information rather than live ID signals.
    // ------------------------------------------------------------

    always_comb begin

        if (id_ex_jal)
            next_pc = ex_jump_target;

        else if (ex_branch_taken)
            next_pc = ex_branch_target;

        else
            next_pc = pc_plus_4;

    end


    // ============================================================
    // IF/ID PIPELINE REGISTER
    // ============================================================

    always_ff @(posedge clk or posedge reset) begin

        if (reset) begin
            if_id_valid <= 1'b0;
            if_id_pc          <= 32'b0;
            if_id_instruction <= 32'b0;
        end

        else begin
            if_id_valid <= 1'b1;
            if_id_pc          <= pc_value;
            if_id_instruction <= instruction;
        end

    end


    // ============================================================
    // ID STAGE
    // ============================================================

    // Decode register addresses from the instruction currently
    // stored in the IF/ID pipeline register.

    assign rs1 = if_id_instruction[19:15];
    assign rs2 = if_id_instruction[24:20];
    assign rd  = if_id_instruction[11:7];


    control_unit control_inst (
        .opcode      (if_id_instruction[6:0]),
        .funct3      (if_id_instruction[14:12]),
        .funct7      (if_id_instruction[31:25]),

        .jump        (jump),
        .imm_sel     (imm_sel),

        .reg_write   (reg_write),
        .alu_src     (alu_src),

        .mem_read    (mem_read),
        .mem_write   (mem_write),

        .branch      (branch),
        .mem_to_reg  (mem_to_reg),

        .alu_control (alu_control)
    );

    logic regfile_write_enable;
    assign regfile_write_enable = mem_wb_valid && mem_wb_reg_write;
    
    register_file regfile_inst (
        .clk          (clk),
        .reset        (reset),

        // ID-stage read ports
        .read_addr_1  (rs1),
        .read_addr_2  (rs2),

        // WB-stage write port
        .write_addr   (mem_wb_rd),
        .write_data   (write_data),
        .write_enable (regfile_write_enable),

        .read_data_1  (read_data_1),
        .read_data_2  (read_data_2)
    );


    immediate_generator imm_gen_inst (
        .instruction (if_id_instruction),
        .imm_sel     (imm_sel),
        .immediate   (immediate)
    );


    // ============================================================
    // ID/EX PIPELINE REGISTER
    // ============================================================

    always_ff @(posedge clk or posedge reset) begin

        if (reset) begin

            id_ex_pc          <= 32'b0;
            id_ex_valid <= 1'b0;
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
            id_ex_valid <= if_id_valid;
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


    // ============================================================
    // EX STAGE
    // ============================================================

   //00 = use normal ID/EX register value
   //10 = take newer value from EX/MEM
   //01 = take value from MEM/WB
   logic [1:0] forward_a;
   logic [1:0] forward_b;
   logic [31:0] forwarded_rs1_data;
   logic [31:0] forwarded_rs2_data;

   
    // ALU source-B mux
    assign alu_operand_b = id_ex_alu_src ? id_ex_immediate : forwarded_rs2_data;


    alu alu_inst (
        .operand_a(forwarded_rs1_data),
        .operand_b   (alu_operand_b),
        .alu_control (id_ex_alu_control),
        .result      (alu_result)
    );


    // Branch comparison is performed using the operands belonging
    // to the instruction currently in EX.

    branch_unit branch_inst (
        .branch       (id_ex_branch),
        .funct3       (id_ex_funct3),
        .operand_a    (id_ex_rs1_data),
        .operand_b    (id_ex_rs2_data),
        .branch_taken (ex_branch_taken)
    );


    // Branch/JAL targets use the PC and immediate belonging to the
    // instruction currently in EX.

    assign ex_branch_target = id_ex_pc + id_ex_immediate;
    assign ex_jump_target   = id_ex_pc + id_ex_immediate;

    // JAL writes the address of the instruction following the JAL.
    assign ex_pc_plus_4 = id_ex_pc + 32'd4;

    
   always_comb begin
    forward_a = 2'b00;
    forward_b = 2'b00;

    if (ex_mem_reg_write && (ex_mem_rd != 5'd0) &&(ex_mem_rd == id_ex_rs1))
        forward_a = 2'b10;
    else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
        forward_a = 2'b01;

    end

    if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
        forward_b = 2'b10;
    else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
        forward_b = 2'b01;

end
end

always_comb begin

    case (forward_a)
        2'b10:   forwarded_rs1_data = ex_mem_alu_result;
        2'b01:   forwarded_rs1_data = write_data;
        default: forwarded_rs1_data = id_ex_rs1_data;
    endcase

    case (forward_b)
        2'b10:   forwarded_rs2_data = ex_mem_alu_result;
        2'b01:   forwarded_rs2_data = write_data;
        default: forwarded_rs2_data = id_ex_rs2_data;
    endcase

end
    // ============================================================
    // EX/MEM PIPELINE REGISTER
    // ============================================================

    always_ff @(posedge clk or posedge reset) begin

        if (reset) begin
            ex_mem_valid <= 1'b0;
            ex_mem_alu_result <= 32'b0;
            ex_mem_rs2_data   <= 32'b0;
            ex_mem_pc_plus_4  <= 32'b0;
            ex_mem_rd         <= 5'b0;

            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_mem_to_reg <= 1'b0;
            ex_mem_jump       <= 1'b0;

        end

        else begin
            ex_mem_valid <= id_ex_valid;
            ex_mem_alu_result <= alu_result;
            ex_mem_rs2_data   <= id_ex_rs2_data;
            ex_mem_pc_plus_4  <= ex_pc_plus_4;
            ex_mem_rd         <= id_ex_rd;

            ex_mem_reg_write  <= id_ex_reg_write;

            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;

            ex_mem_mem_to_reg <= id_ex_mem_to_reg;
            ex_mem_jump       <= id_ex_jal;

        end

    end


    // ============================================================
    // MEM STAGE
    // ============================================================
    logic data_mem_write_enable;
    assign data_mem_write_enable = ex_mem_valid && ex_mem_mem_write;
    data_memory dmem_inst (
        .clk       (clk),
        .reset     (reset),

        .mem_read  (ex_mem_mem_read),
        .mem_write (data_mem_write_enable),

        .address   (ex_mem_alu_result),
        .write_data(ex_mem_rs2_data),

        .read_data (mem_read_data)
    );


    // ============================================================
    // MEM/WB PIPELINE REGISTER
    // ============================================================

    always_ff @(posedge clk or posedge reset) begin

        if (reset) begin
            mem_wb_valid <= 1'b0;
            mem_wb_mem_read_data <= 32'b0;
            mem_wb_alu_result    <= 32'b0;
            mem_wb_pc_plus_4     <= 32'b0;
            mem_wb_rd            <= 5'b0;

            mem_wb_reg_write     <= 1'b0;
            mem_wb_mem_to_reg    <= 1'b0;
            mem_wb_jump          <= 1'b0;

        end

        else begin
            mem_wb_valid <= ex_mem_valid;
            mem_wb_mem_read_data <= mem_read_data;
            mem_wb_alu_result    <= ex_mem_alu_result;
            mem_wb_pc_plus_4     <= ex_mem_pc_plus_4;
            mem_wb_rd            <= ex_mem_rd;

            mem_wb_reg_write     <= ex_mem_reg_write;
            mem_wb_mem_to_reg    <= ex_mem_mem_to_reg;
            mem_wb_jump          <= ex_mem_jump;

        end

    end


    // ============================================================
    // WB STAGE
    // ============================================================

    // Write-back source selection:
    //
    // JAL        -> PC + 4
    // LW         -> Data Memory
    // Arithmetic -> ALU result

    always_comb begin

        if (mem_wb_jump)
            write_data = mem_wb_pc_plus_4;

        else if (mem_wb_mem_to_reg)
            write_data = mem_wb_mem_read_data;

        else
            write_data = mem_wb_alu_result;

    end


endmodule