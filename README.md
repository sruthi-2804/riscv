# RV32I 5-Stage Pipelined CPU (SystemVerilog)

A five-stage pipelined RV32I processor written from scratch in SystemVerilog, verified with directed
regression, bound SystemVerilog Assertions and a constrained-random campaign against an independent
architectural reference model, instrumented with pipeline performance counters, and taken through
Vivado synthesis and post-route timing closure on a Zynq-7010.

Every number on this page was produced by a simulation or Vivado run in this repository. Nothing is
estimated or extrapolated.

| | |
|---|---|
| **ISA** | RV32I integer subset (no system/CSR instructions — see [Limitations](#limitations)) |
| **Pipeline** | 5-stage IF / ID / EX / MEM / WB, in-order, single-issue |
| **Hazards** | EX/MEM + MEM/WB forwarding, load-use interlock, branch/jump flush |
| **Directed regression** | 331 / 331 checks, 0 errors |
| **Assertions** | 14 SVA properties, 0 failures |
| **Random campaign** | 1,440 programs, 41,846 instructions, 0 mismatches |
| **FPGA** | xc7z010iclg225-1L — 4,640 LUT, 9,636 FF, **103.1 MHz** post-route |

---

## Pipeline

```
    IF              ID              EX             MEM            WB
 ┌────────┐     ┌────────┐     ┌─────────┐    ┌─────────┐    ┌────────┐
 │   PC   │────>│ decode │────>│   ALU   │───>│  data   │───>│  reg   │
 │  imem  │     │ regfile│     │ branch  │    │  memory │    │ write  │
 └────────┘     │  imm   │     │  unit   │    │  (B/H/W)│    │  back  │
      ^         └────────┘     └─────────┘    └─────────┘    └────────┘
      │           IF/ID           ID/EX          EX/MEM         MEM/WB
      │             │               │               │              │
      │             │               │  ┌────────────┘              │
      │             │               │  │   EX/MEM forward (10)     │
      │             │               │<─┤                           │
      │             │               │  │   MEM/WB forward (01)     │
      │             │               │  └───────────────────────────┘
      │             │               │
      │             │        ┌──────┴───────┐
      │             │        │ branch taken │
      │<────────────┴────────┤ JAL / JALR   │   redirect + flush
      │   load-use stall     └──────────────┘   (kills IF/ID + ID/EX)
      │   freezes PC & IF/ID
      │   inserts ID/EX bubble
```

**Forwarding.** Two paths feed the EX operand muxes: `2'b10` from EX/MEM and `2'b01` from MEM/WB.
An EX/MEM match always wins over a simultaneous MEM/WB match, so the newer value is used. `x0` is
excluded as a forwarding producer. Both paths, the priority rule and the `x0` exclusion are each
covered by a directed test and by a bound assertion.

**Load-use interlock.** A load in EX with a dependent consumer in ID freezes the PC and the IF/ID
register and inserts a bubble into ID/EX for **exactly one cycle**; the consumer then takes the
loaded value over the MEM/WB path. The one-cycle duration is measured at cycle level, not inferred
from the final result — the check fails on a 0-cycle stall *and* on a 2-or-more-cycle stall.

Source-operand qualification matters here: `LUI`, `AUIPC` and `JAL` have no source registers at all,
and `I`-type ALU, `JALR` and loads use `rs1` only, so their `rs2` field is immediate bits. The hazard
unit decodes actual operand usage rather than comparing raw instruction fields, and a directed test
places a load before each of those six cases with the bit field deliberately aliasing the load's `rd`
to prove no false stall is raised.

**Control flow.** Branches, `JAL` and `JALR` resolve in EX and redirect the PC, killing the two
younger instructions in IF/ID and ID/EX. `JALR` masks its target to `(rs1 + imm) & ~1`.

**Bubble and flush safety.** Every pipeline register carries a valid bit. An invalid entry can never
write the register file or data memory, and a bubble carries no live control signals — enforced by
assertions on every cycle of every CPU-level test.

---

## Implemented instructions

| Class | Instructions |
|---|---|
| ALU register | `ADD` `SUB` `SLL` `SLT` `SLTU` `XOR` `SRL` `SRA` `OR` `AND` |
| ALU immediate | `ADDI` `SLTI` `SLTIU` `XORI` `ORI` `ANDI` `SLLI` `SRLI` `SRAI` |
| Loads | `LB` `LH` `LW` `LBU` `LHU` |
| Stores | `SB` `SH` `SW` |
| Branches | `BEQ` `BNE` `BLT` `BGE` `BLTU` `BGEU` |
| Jumps | `JAL` `JALR` |
| Upper immediate | `LUI` `AUIPC` |

### Limitations

Deliberately **not** implemented. These are scope boundaries, not known bugs:

- **No system instructions** — `FENCE`, `ECALL`, `EBREAK` and the Zicsr CSR instructions are not
  decoded. This is an RV32I *integer subset*, not a spec-complete RV32I core.
- **No exceptions, traps, interrupts or privilege modes.**
- **No misaligned access handling.** Behaviour on a misaligned load/store is undefined; the random
  generator excludes such accesses by construction.
- **No M/A/F/D extensions.**
- **No caches, no branch prediction** — branches are always taken as not-taken until resolved in EX,
  costing two cycles per taken branch.
- **Memories are on-chip arrays** initialised in RTL, not external interfaces.
- **Not a board-level design.** There is no top-level wrapper with pin assignments; see
  [Synthesis and timing](#synthesis-and-timing).

---

## Verification

### Directed regression — 331 / 331 checks, 0 errors

| Suite | Checks | What it covers |
|---|---|---|
| `tb_branch_unit_check` | 22 | All six branch comparisons, signed vs unsigned, invalid `funct3` |
| `tb_control_unit_check` | 60 | Decode safety, safe defaults on illegal encodings |
| `tb_data_memory_subword_check` | 9 | Byte-enable lane isolation |
| `tb_cpu_alu_hazard_check` | 38 | CPU-level ALU coverage, EX/MEM-over-MEM/WB priority, `x0` exclusion, backward-branch loop, one-cycle stall proof |
| `tb_cpu_branch_check` | 16 | All branch types at CPU level, branch on a forwarded operand |
| `tb_cpu_jal_check` | 38 | `JAL`/`JALR`, backward `JAL`, `JALR` LSB masking, false-stall exclusion |
| `tb_cpu_subword_utype_check` | 38 | Sub-word loads/stores, sign vs zero extension, `LUI`/`AUIPC` |
| `tb_cpu_loop_check` | 64 | Sum, Fibonacci, nested and long mixed loop workloads |
| `tb_cpu_jalr_hazard_check` | 46 | `JALR` forwarded base (EX/MEM and MEM/WB), `LW`→`JALR`, adjacent control flow |

Two further suites cover the performance counters (`tb_perf_counter_check`, 44 checks and
`tb_cpu_cpi_bench`, 50 checks), for **425 checks in total** across 11 suites.

### Assertions — 14 properties, 0 failures

`riscv_cpu_sva.sv` attaches to the CPU with `bind`, so no RTL file is modified. Properties cover
load-use stall effects (PC freeze, IF/ID freeze, ID/EX bubble), branch and jump flush, EX/MEM
forwarding priority, `x0` forwarding exclusion, bubble write suppression and reset state.

### Randomized verification against a reference model

Programs are generated by a deterministic xorshift PRNG — every program is reproducible from its
32-bit seed. An independent architectural reference model (32 registers, PC control flow, 256-word
data memory, RV32I semantics) executes each program, and the DUT's **committed** architectural state
(register file + data memory) is compared against it. Transient pipeline state is never compared, so
flushed instructions cannot be mistaken for retired ones.

**Final expanded campaign** — 4 seeds (`20260919`, `1`, `12345`, `2718281828`), 8 generation phases:

| | |
|---|---|
| Programs | **1,440** |
| Architectural instructions executed | **41,846** |
| Backward-taken branches | **3,379** |
| Reference-model mismatches | **0** |
| Non-terminating / skipped programs | **0** |

### Backward branches and loops

Backward control flow is covered two ways. Directed workloads in `tb_cpu_loop_check` run a
sum-1-to-100 loop, an iterative Fibonacci writing ten terms to memory, a two-level nested loop and a
64-iteration mixed workload of ALU, forwarding, store, load-use and branch — the longest retires
roughly 520 instructions and produces 65 load-use stalls, each proven to be exactly one cycle. Each
loop keeps a shadow counter after its back edge, so a flush failure shows up as a wrong retirement
count rather than passing silently.

In the random generator, backward branches are emitted only as a counted-loop construct whose trip
count is fixed at generation time by a countdown register that no body instruction may write and
that is compared against `x0`. Loop slots are fenced off from outside branch and jump targets, so no
program can jump past a loop's initialisation. Termination is structural rather than probabilistic —
across 1,440 programs, zero failed to terminate.

---

## Performance

Four 64-bit counters (`cycle_count`, `instret_count`, `stall_count`, `flush_count`) are read-only
sinks: nothing they observe is driven back into the datapath, and they sit behind
`translate_off`/`translate_on`, so they are excluded from synthesis and cost no fabric. Retirement is
qualified by the MEM/WB valid bit, so stores and branches count while bubbles and wrong-path entries
do not.

Measured over an identical window per workload — reset release to sentinel commit, nothing
subtracted:

| Workload | Retired | Cycles | Stall cycles | Flush events | CPI |
|---|---|---|---|---|---|
| Straight-line (200 independent `ADDI`) | 201 | 205 | 0 | 0 | **1.0199** |
| Load-use (80 dependent `LW`/`ADDI` pairs) | 163 | 247 | 80 | 0 | **1.5153** |
| Branch taken (100 taken `BEQ`) | 101 | 305 | 0 | 100 | **3.0198** |
| Branch not taken (200 `BNE`) | 201 | 205 | 0 | 0 | **1.0199** |
| `JAL` (100 forward jumps) | 101 | 305 | 0 | 100 | **3.0198** |
| `JALR` (100 indirect jumps) | 101 | 305 | 0 | 100 | **3.0198** |

Every workload satisfies `cycles = 4 + retired + stalls + 2 × flushes` exactly — four pipeline-fill
cycles, one cycle per commit, one per stall, two discarded per redirect. The model is compared
against hardware in the testbench, so the model is under test too.

The same counters were run across the full 1,440-program random campaign. The DUT's flush count
matched the reference model's count of executed control transfers **exactly** — 4,710 against 4,710,
and exactly per type (132 `JAL`, 66 `JALR`, 955 taken branches on the lead seed).

---

## Synthesis and timing

Target `xc7z010iclg225-1L` (Zynq-7010), Vivado 2026.1.

| Resource | Used | Available | % |
|---|---|---|---|
| Slice LUTs | **4,640** | 17,600 | 26.4 |
| Slice registers | **9,636** | 35,200 | 27.4 |
| Block RAM | **0** | 60 | 0 |
| DSP | **0** | 80 | 0 |

| Clock target | Frequency | Post-synth WNS | Post-route WNS | Result |
|---|---|---|---|---|
| 10.000 ns | 100.0 MHz | +0.489 ns | — | pass |
| **9.700 ns** | **103.1 MHz** | +0.189 ns | **+0.183 ns** | **pass** |
| 9.600 ns | 104.2 MHz | +0.089 ns | −0.020 ns | fails post-route |
| 9.500 ns | 105.3 MHz | −0.011 ns | — | fails |

**Fmax = 103.1 MHz post-route.** Each candidate period was re-synthesised and re-implemented rather
than extrapolated from slack at a looser target — timing-driven tools optimise to whatever target
they are given, and in this design the naive extrapolation from the 100 MHz run would have claimed
105 MHz, which does not actually route.

**Critical path:** ID/EX source register → operand forwarding mux → EX branch comparator (carry
chain) → flush term → IF/ID register control. About 10 logic levels, roughly 74% routing delay. This
is the expected critical path for a 5-stage pipeline that resolves branches in EX with forwarded
operands.

**No block RAM is inferred.** The flip-flop count decomposes as data memory 256×32 = 8,192, register
file 32×32 = 1,024, and roughly 415 pipeline/PC registers. The data memory clears all 256 locations
in a single cycle on reset, which block RAM cannot do, so it maps to fabric registers; the
instruction memory is initialised in RTL and never written at runtime, so it maps to a LUT ROM. That
is a design choice, and it accounts for most of the area.

**Measurability note.** `riscv_cpu` has no output ports, so synthesising it directly produces an
empty netlist — with no observable state every register is dead logic and is optimised away.
`riscv_cpu_synth_top.sv` exposes write-back and store control as read-only taps so the core survives
optimisation. It adds 6 LUTs (0.1%) and is not a board-level top: it assigns no package pins, so
I/O timing is out of scope and the figures above describe the internal register-to-register path.

---

## Repository structure

```
riscv/riscv.srcs/
  sources_1/new/          RTL: alu, branch, control_unit, data_memory,
                          immediate, instruction_memory, program_counter,
                          register_file, riscv_cpu_synth_top
  constrs_1/new/          riscv_cpu.xdc  (clock constraint only)
  sim_1/new/
    regression/           9 directed self-checking suites
    random/               constrained-random + reference model
    sva/                  14 bound assertions
    perf/                 counter validation + CPI workloads
riscv_cpu/riscv_cpu.srcs/
  sources_1/new/          riscv_cpu.sv   (pipeline top)
```

## Running the simulations

Requires Vivado's simulator (`xvlog` / `xelab`) on `PATH`. From a scratch directory:

```sh
# 1. compile RTL + the suite you want (order matters: RTL first)
xvlog -sv \
  <repo>/riscv/riscv.srcs/sources_1/new/*.sv \
  <repo>/riscv_cpu/riscv_cpu.srcs/sources_1/new/riscv_cpu.sv \
  <repo>/riscv/riscv.srcs/sim_1/new/sva/riscv_cpu_sva.sv \
  <repo>/riscv/riscv.srcs/sim_1/new/regression/tb_cpu_loop_check.sv

# 2. elaborate with the SVA bind wrapper as a second top, and run
xelab tb_cpu_loop_check riscv_cpu_sva_bind -s run --relax -R
```

Swap the last source file and the top name for any other suite:

| Goal | Top module |
|---|---|
| Backward-branch / loop workloads | `tb_cpu_loop_check` |
| `JALR` corner cases and combined hazards | `tb_cpu_jalr_hazard_check` |
| Forwarding priority, `x0`, one-cycle stall | `tb_cpu_alu_hazard_check` |
| Randomized vs reference model | `tb_cpu_random_check` |
| Counter validation | `tb_perf_counter_check` |
| CPI workloads | `tb_cpu_cpi_bench` |

The randomized suite defaults to seed `20260919`; other seeds are reproduced by changing
`base_seed` in `tb_cpu_random_check.sv`. Each suite prints a per-check `PASS`/`FAIL` log and ends
with a `<NAME>_TB: ALL PASS` banner.
