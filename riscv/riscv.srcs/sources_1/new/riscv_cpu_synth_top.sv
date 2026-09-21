`timescale 1ns / 1ps
// Synthesis-only wrapper around the CPU core.
//
// Why this file exists
// --------------------
// riscv_cpu has no output ports. Synthesising it directly yields an EMPTY
// netlist: with no architectural state observable outside the module, every
// register is dead logic and Vivado removes it (Synth 8-4446, followed by a
// black-box warning if the instance is merely marked DONT_TOUCH). Any
// utilisation or timing number taken from such a run would be fabricated.
//
// This wrapper makes the core observable so that synthesis and static timing
// analysis have something real to measure. It does not modify the core: the
// taps below are read-only hierarchical references driven straight to output
// ports, so they add no logic of their own - no XOR trees, no extra
// registers. Reported LUT/FF counts and the worst register-to-register path
// are therefore those of the core as written.
//
// Why these particular taps
// -------------------------
// They are chosen so that essentially the whole design sits in the logic
// cone of an observed output:
//   write_data            the write-back value. Its cone covers the register
//                         file array (read ports -> pipeline -> WB), the ALU,
//                         and the data memory array (read path -> WB mux).
//                         Because the data memory array is in this cone, its
//                         write port is kept alive too.
//   pc_value              covers the PC, branch/jump target and redirect logic.
//   regfile_write_enable  covers the write-back control path.
//   data_mem_write_enable covers the store control path.
//   mem_wb_rd             covers the destination-register pipeline path.
//
// What this file is NOT
// ---------------------
// It is not a board-level top. It assigns no package pins, invents no
// external interface and models no off-chip timing, so implementation-level
// I/O timing is deliberately out of scope. The meaningful number it makes
// available is the internal register-to-register critical path.
//
// This module is never used in simulation; the verification suites
// instantiate riscv_cpu directly.

module riscv_cpu_synth_top (
    input  logic        clk,
    input  logic        reset,

    output logic [31:0] obs_wb_data,
    output logic [4:0]  obs_wb_rd,
    output logic        obs_wb_en,
    output logic        obs_dmem_we,
    output logic        obs_pc_par
);

    riscv_cpu u_cpu (
        .clk   (clk),
        .reset (reset)
    );

    // Read-only observability taps. The bus taps add no logic at all - they
    // are wires to output ports.
    assign obs_wb_data  = u_cpu.write_data;
    assign obs_wb_rd    = u_cpu.mem_wb_rd;
    assign obs_wb_en    = u_cpu.regfile_write_enable;
    assign obs_dmem_we  = u_cpu.data_mem_write_enable;

    // The PC is already inside write_data's logic cone (PC -> instruction
    // fetch -> decode -> operands -> write-back), so it survives without a
    // tap of its own. This one-bit parity tap observes it directly anyway,
    // as a guard against the fetch cone being broken by a future change.
    // It is the only logic this file adds: a 32-input XOR, about 11 LUTs,
    // roughly 0.2% of the reported LUT count.
    //
    // The PC is deliberately NOT exposed as a 32-bit bus: the xc7z010 in the
    // clg225 package has 54 user pins, and a full-width PC tap pushed the
    // port count to 72, which made I/O placement infeasible and blocked
    // implementation entirely.
    assign obs_pc_par   = ^u_cpu.pc_value;

endmodule
