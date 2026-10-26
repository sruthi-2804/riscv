#!/usr/bin/env bash
#
# Compile and run every simulation suite, then print a pass/fail summary.
#
# Requires Vivado's simulator (xvlog / xelab) on PATH. See the README section
# "Running the simulations" for why the open-source simulators are not an
# option here yet.
#
# Usage:
#   ./run_all.sh              # 11 self-checking suites
#   ./run_all.sh --random     # the above plus the 4-seed random campaign
#   ./run_all.sh --only tb_cpu_loop_check
#
# Artifacts (logs and xsim's working files) land in build/, which is not
# tracked. Each suite is run in its own subdirectory because xelab writes
# xsim.dir into the current directory and parallel suites would collide.

set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/riscv/riscv.srcs/sources_1/new"
CPU="$ROOT/riscv_cpu/riscv_cpu.srcs/sources_1/new/riscv_cpu.sv"
SIM="$ROOT/riscv/riscv.srcs/sim_1/new"
SVA="$SIM/sva/riscv_cpu_sva.sv"
BUILD="$ROOT/build"

# Suites that do not instantiate riscv_cpu, so the SVA bind has no target and
# is left out of the elaboration.
UNIT_SUITES=(
  "regression/tb_branch_unit_check.sv          tb_branch_unit_check"
  "regression/tb_control_unit_check.sv         tb_control_unit_check"
  "regression/tb_data_memory_subword_check.sv  tb_data_memory_subword_check"
)

# CPU-level suites. These elaborate riscv_cpu_sva_bind as a second top, so the
# 14 assertions are checked on every cycle of every one of these runs.
CPU_SUITES=(
  "regression/tb_cpu_alu_hazard_check.sv       tb_cpu_alu_hazard_check"
  "regression/tb_cpu_branch_check.sv           tb_cpu_branch_check"
  "regression/tb_cpu_jal_check.sv              tb_cpu_jal_check"
  "regression/tb_cpu_jalr_hazard_check.sv      tb_cpu_jalr_hazard_check"
  "regression/tb_cpu_loop_check.sv             tb_cpu_loop_check"
  "regression/tb_cpu_subword_utype_check.sv    tb_cpu_subword_utype_check"
  "perf/tb_perf_counter_check.sv               tb_perf_counter_check"
  "perf/tb_cpu_cpi_bench.sv                    tb_cpu_cpi_bench"
)

RANDOM_SUITE="random/tb_cpu_random_check.sv    tb_cpu_random_check"
RANDOM_SEEDS=(20260919 1 12345 2718281828)

WITH_RANDOM=0
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --random) WITH_RANDOM=1; shift ;;
    --only)   ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$BASH_SOURCE"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! command -v xvlog >/dev/null || ! command -v xelab >/dev/null; then
  echo "ERROR: xvlog/xelab not found on PATH." >&2
  echo "       This project needs Vivado's simulator; see the README." >&2
  exit 127
fi

mkdir -p "$BUILD"
PASS=(); FAIL=()

# run_suite <relative-tb-path> <top-module> <use-sva: 0|1> [extra xelab args...]
run_suite() {
  local tb="$1" top="$2" use_sva="$3"; shift 3
  local label="${top}${LABEL_SUFFIX:-}"
  local dir="$BUILD/$label" log="$BUILD/$label.log"

  rm -rf "$dir"; mkdir -p "$dir"

  local sources=("$SRC"/*.sv "$CPU")
  local tops=("$top")
  if [ "$use_sva" = 1 ]; then
    sources+=("$SVA")
    tops+=(riscv_cpu_sva_bind)
  fi
  sources+=("$SIM/$tb")

  printf '%-34s ' "$label"
  if ( cd "$dir" \
       && xvlog -sv "${sources[@]}" \
       && xelab "${tops[@]}" -s run --relax -R "$@" ) >"$log" 2>&1
  then
    # xvlog/xelab exit 0 even when the testbench itself reported errors, so the
    # verdict comes from the suite's own banner, not from the exit status.
    if grep -q ': ALL PASS' "$log" && ! grep -q ': FAILED' "$log"; then
      echo "PASS"; PASS+=("$label"); return 0
    fi
    echo "FAIL  (no ALL PASS banner; see ${log#$ROOT/})"
  else
    echo "FAIL  (compile/elaborate; see ${log#$ROOT/})"
  fi
  FAIL+=("$label"); return 1
}

echo "=== RV32I pipeline regression ==="
echo

for entry in "${UNIT_SUITES[@]}" "${CPU_SUITES[@]}"; do
  read -r tb top <<<"$entry"
  [ -n "$ONLY" ] && [ "$ONLY" != "$top" ] && continue
  case " ${UNIT_SUITES[*]} " in
    *"$tb"*) run_suite "$tb" "$top" 0 ;;
    *)       run_suite "$tb" "$top" 1 ;;
  esac
done

if [ "$WITH_RANDOM" = 1 ] && [ -z "$ONLY" ]; then
  echo
  echo "--- random campaign (4 seeds, 360 programs each) ---"
  read -r tb top <<<"$RANDOM_SUITE"
  for seed in "${RANDOM_SEEDS[@]}"; do
    LABEL_SUFFIX=".seed$seed" \
      run_suite "$tb" "$top" 1 -testplusarg "BASE_SEED=$seed"
  done
  unset LABEL_SUFFIX
  echo
  echo "Per-seed cycle/retire counters and CPI:"
  grep -H 'aggregate CPI' "$BUILD"/tb_cpu_random_check.seed*.log 2>/dev/null \
    | sed "s|$BUILD/||" || echo "  (none found)"
  echo
  echo "The campaign totals in the README are these per-seed counters summed"
  echo "across the four runs; the aggregate CPI is the summed cycles divided"
  echo "by the summed retired instructions."
fi

echo
echo "=== summary ==="
echo "passed: ${#PASS[@]}"
echo "failed: ${#FAIL[@]}"
if [ "${#FAIL[@]}" -ne 0 ]; then
  printf '  %s\n' "${FAIL[@]}"
  echo
  echo "Logs are in ${BUILD#$ROOT/}/."
  exit 1
fi
echo "All suites passed."
