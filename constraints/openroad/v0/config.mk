# OpenROAD Flow Scripts configuration for the registered V0 evaluation top.

export PLATFORM = nangate45
export DESIGN_NAME = butterfly_comb_eval

export VERILOG_FILES = \
    /work/rtl/common/sat_q15.sv \
    /work/rtl/common/rne_sat_q30_to_q15.sv \
    /work/rtl/v0/butterfly_comb.sv \
    /work/rtl/eval/butterfly_comb_eval.sv

export SDC_FILE = /work/constraints/openroad/v0/constraint.sdc

# Fixed-frequency comparison point: 2.0 ns = 500 MHz.
export CLOCK_PORT = clk
export CLOCK_PERIOD = 2.000

# Keep physical-design assumptions identical between V0 and V1.
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export PLACE_DENSITY_LB_ADDON = 0.10
