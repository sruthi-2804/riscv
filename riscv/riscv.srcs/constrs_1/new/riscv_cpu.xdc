# ---------------------------------------------------------------------------
# Minimal timing constraint for the 5-stage RISC-V core.
#
# Scope: this file constrains the CPU clock and nothing else. The core is not
# a board-level design - it has no output ports and no package pin assignment
# - so no IOSTANDARD or PACKAGE_PIN properties are set here and none are
# invented. Its purpose is to give synthesis and static timing analysis a
# defined clock period so that the internal register-to-register paths can be
# characterised.
#
# 10.000 ns = 100 MHz is the initial analysis target.
#
# Note on what is deliberately NOT constrained: clk and reset are the only
# ports, and there are no outputs, so there are no meaningful I/O timing
# paths to constrain. No set_input_delay / set_output_delay is declared, and
# reset is NOT declared a false path - doing so would remove real synchronous
# reset fanout from analysis and flatter the reported slack.
# ---------------------------------------------------------------------------

create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]
