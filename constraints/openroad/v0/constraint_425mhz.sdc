# Fmax sweep point: 425 MHz timing environment for the V0 evaluation wrapper.
# This constraint is specific to the V0 frequency sweep.

create_clock -name core_clock -period 2.35294 [get_ports clk]
set_clock_uncertainty 0.050 [get_clocks core_clock]
set_clock_transition 0.050 [get_clocks core_clock]

# Reserve 10% of the cycle at each external interface. The core arithmetic
# paths remain register-to-register inside the evaluation wrapper.
set data_inputs [get_ports {valid_in a_re a_im b_re b_im w_re w_im}]
set_input_delay 0.235294 -clock core_clock $data_inputs
set_output_delay 0.235294 -clock core_clock [all_outputs]
set_input_transition 0.050 $data_inputs
set_load 0.010 [all_outputs]

# Reset is a synchronous functional control, but it is excluded from the
# performance comparison because reset assertion is not a throughput path.
set_false_path -from [get_ports rst]
