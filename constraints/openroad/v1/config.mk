# OpenROAD Flow Scripts configuration for the registered V1 evaluation top.

export PLATFORM = nangate45
export DESIGN_NAME = butterfly_pipe_eval

export VERILOG_FILES = \
    /work/rtl/v1/butterfly_pipe.sv \
    /work/rtl/eval/butterfly_pipe_eval.sv

export SDC_FILE = /work/constraints/openroad/v1/constraint.sdc

# Fixed-frequency comparison point: 2.0 ns = 500 MHz.
export CLOCK_PORT = clk
export CLOCK_PERIOD = 2.000

# Keep physical-design assumptions identical between V0 and V1.
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export PLACE_DENSITY_LB_ADDON = 0.10
