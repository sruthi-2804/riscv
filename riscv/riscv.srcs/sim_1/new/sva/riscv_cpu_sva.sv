`timescale 1ns / 1ps
// Phase 9.2: SVA checker for the 5-stage pipeline, attached with `bind` so
// no RTL file is modified. Signal timing notes:
//  - load_use_hazard / control_flush are combinational in cycle N; their
//    architectural effect (freeze / bubble / flush) appears in the pipeline
//    registers at N+1, hence |=> with $past/$stable for those checks.
//  - forwarding selects and write-enable gates are combinational in the same
//    cycle as their operands, hence same-cycle |->.

module riscv_cpu_sva (
    input logic        clk,
    input logic        reset,

    // hazard / flush
    input logic        load_use_hazard,
    input logic        control_flush,
    input logic        ex_branch_taken,

    // IF / IF-ID
    input logic [31:0] pc_value,
    input logic        if_id_valid,
    input logic [31:0] if_id_instruction,

    // ID/EX
    input logic        id_ex_valid,
    input logic        id_ex_reg_write,
    input logic        id_ex_mem_write,
    input logic        id_ex_branch,
    input logic        id_ex_jal,
    input logic        id_ex_jalr,
    input logic [4:0]  id_ex_rs1,
    input logic [4:0]  id_ex_rs2,

    // forwarding
    input logic [1:0]  forward_a,
    input logic [1:0]  forward_b,
    input logic        ex_mem_valid,
    input logic        ex_mem_reg_write,
    input logic [4:0]  ex_mem_rd,
    input logic        mem_wb_valid,
    input logic        mem_wb_reg_write,
    input logic [4:0]  mem_wb_rd,

    // architectural side-effect gates
    input logic        regfile_write_enable,
    input logic        data_mem_write_enable
);

    // Proof that the bind actually attached in this simulation.
    initial $display("SVA: riscv_cpu_sva bound at %m");

    // A1: a load-use stall freezes the PC for the next cycle
    a1_stall_freezes_pc: assert property (@(posedge clk) disable iff (reset)
        load_use_hazard |=> (pc_value == $past(pc_value)))
        else $error("A1: PC advanced during load-use stall");

    // A2: a load-use stall holds the IF/ID register contents
    a2_stall_freezes_ifid: assert property (@(posedge clk) disable iff (reset)
        load_use_hazard |=> ($stable(if_id_instruction) && $stable(if_id_valid)))
        else $error("A2: IF/ID changed during load-use stall");

    // A3: a load-use stall inserts a bubble into ID/EX
    a3_stall_bubbles_idex: assert property (@(posedge clk) disable iff (reset)
        load_use_hazard |=> !id_ex_valid)
        else $error("A3: ID/EX not bubbled after load-use stall");

    // A4: a valid taken branch in EX raises control_flush
    a4_taken_branch_flushes: assert property (@(posedge clk) disable iff (reset)
        (id_ex_valid && ex_branch_taken) |-> control_flush)
        else $error("A4: taken branch did not raise control_flush");

    // A5: a valid JAL or JALR in EX raises control_flush
    a5_jump_flushes: assert property (@(posedge clk) disable iff (reset)
        (id_ex_valid && (id_ex_jal || id_ex_jalr)) |-> control_flush)
        else $error("A5: JAL/JALR did not raise control_flush");

    // A6: control_flush kills both younger stages on the next edge
    a6_flush_kills_younger: assert property (@(posedge clk) disable iff (reset)
        control_flush |=> (!if_id_valid && !id_ex_valid))
        else $error("A6: wrong-path IF/ID or ID/EX survived a flush");

    // A7: an EX/MEM producer match always wins the rs1 forwarding mux
    //     (priority over any simultaneous MEM/WB match)
    a7_exmem_priority_rs1: assert property (@(posedge clk) disable iff (reset)
        (ex_mem_valid && ex_mem_reg_write && (ex_mem_rd != 5'd0) &&
         (ex_mem_rd == id_ex_rs1)) |-> (forward_a == 2'b10))
        else $error("A7: EX/MEM rs1 match did not select EX/MEM path");

    // A8: an EX/MEM producer match always wins the rs2 forwarding mux
    a8_exmem_priority_rs2: assert property (@(posedge clk) disable iff (reset)
        (ex_mem_valid && ex_mem_reg_write && (ex_mem_rd != 5'd0) &&
         (ex_mem_rd == id_ex_rs2)) |-> (forward_b == 2'b10))
        else $error("A8: EX/MEM rs2 match did not select EX/MEM path");

    // A9: x0 is never a forwarding producer for either operand
    a9_no_x0_forward_rs1: assert property (@(posedge clk) disable iff (reset)
        (id_ex_rs1 == 5'd0) |-> (forward_a == 2'b00))
        else $error("A9: forwarding selected for rs1 = x0");

    a10_no_x0_forward_rs2: assert property (@(posedge clk) disable iff (reset)
        (id_ex_rs2 == 5'd0) |-> (forward_b == 2'b00))
        else $error("A10: forwarding selected for rs2 = x0");

    // A11: an invalid MEM/WB entry never writes the register file
    a11_bubble_no_regwrite: assert property (@(posedge clk) disable iff (reset)
        !mem_wb_valid |-> !regfile_write_enable)
        else $error("A11: register write from an invalid MEM/WB entry");

    // A12: a bubble in ID/EX carries no write intent at all
    a12_bubble_no_intent: assert property (@(posedge clk) disable iff (reset)
        !id_ex_valid |-> (!id_ex_reg_write && !id_ex_mem_write &&
                          !id_ex_branch && !id_ex_jal && !id_ex_jalr))
        else $error("A12: ID/EX bubble carries live control signals");

    // A13: an invalid EX/MEM entry never writes data memory
    a13_bubble_no_memwrite: assert property (@(posedge clk) disable iff (reset)
        !ex_mem_valid |-> !data_mem_write_enable)
        else $error("A13: memory write from an invalid EX/MEM entry");

    // A14: the cycle after reset, every pipeline valid bit is clear
    a14_reset_clears_valids: assert property (@(posedge clk)
        reset |=> (!if_id_valid && !id_ex_valid &&
                   !ex_mem_valid && !mem_wb_valid))
        else $error("A14: pipeline valid bit set right after reset");

endmodule

// Attach the checker to every riscv_cpu instance without touching the RTL.
// The bind lives in its own module so it can be handed to xelab as an
// additional top and is guaranteed to be elaborated.
module riscv_cpu_sva_bind;

bind riscv_cpu riscv_cpu_sva sva_inst (
    .clk                   (clk),
    .reset                 (reset),
    .load_use_hazard       (load_use_hazard),
    .control_flush         (control_flush),
    .ex_branch_taken       (ex_branch_taken),
    .pc_value              (pc_value),
    .if_id_valid           (if_id_valid),
    .if_id_instruction     (if_id_instruction),
    .id_ex_valid           (id_ex_valid),
    .id_ex_reg_write       (id_ex_reg_write),
    .id_ex_mem_write       (id_ex_mem_write),
    .id_ex_branch          (id_ex_branch),
    .id_ex_jal             (id_ex_jal),
    .id_ex_jalr            (id_ex_jalr),
    .id_ex_rs1             (id_ex_rs1),
    .id_ex_rs2             (id_ex_rs2),
    .forward_a             (forward_a),
    .forward_b             (forward_b),
    .ex_mem_valid          (ex_mem_valid),
    .ex_mem_reg_write      (ex_mem_reg_write),
    .ex_mem_rd             (ex_mem_rd),
    .mem_wb_valid          (mem_wb_valid),
    .mem_wb_reg_write      (mem_wb_reg_write),
    .mem_wb_rd             (mem_wb_rd),
    .regfile_write_enable  (regfile_write_enable),
    .data_mem_write_enable (data_mem_write_enable)
);

endmodule
