# UVM Verification

English | [简体中文](07_uvm_verification_zh-CN.md)

## 1. Scope

This document records the current UVM 1.2 verification environment for the pipelined Radix-2 Butterfly. The environment targets Vivado XSim 2025.1 and verifies `butterfly_pipe` directly. It does not instantiate `butterfly_comb` or either physical-evaluation wrapper.

The UVM run described here combines a small directed smoke sequence with constrained-random stimulus and randomized bubbles. It is evidence for the tested configurations, not proof that the design is absolutely correct for every possible behavior.

## 2. DUT and Timing Contract

`butterfly_pipe` is a three-stage pipeline:

| Stage | Work | Registered or aligned state |
|---|---|---|
| 1 | Complex add and subtract | `S`, `D`, `W`, and `valid_s1` |
| 2 | Four parallel real multiplications | Four 33-bit products, bypassed `Y0`, and `valid_s2` |
| 3 | 34-bit product add/subtract, RNE, and saturation | Four outputs, four saturation flags, and `valid_out` |

An input observed with `rst=0` and `valid_in=1` at sampling edge `t` must produce its corresponding valid output at edge `t+2`. The core latency is therefore two cycles. The initiation interval is `II=1`, so adjacent valid transactions are legal and must preserve order.

Reset is synchronous and active high. The current UVM test applies only the initial reset; a mid-flight reset sequence is not yet implemented.

## 3. UVM Structure

The environment is implemented in `tb/uvm/butterfly_uvm_pkg.sv` and connected through `tb/uvm/butterfly_if.sv`.

| Element | Responsibility |
|---|---|
| `butterfly_item` | Holds six signed Q1.15 input components, observed output fields, cycle metadata, and `idle_cycles_before` |
| `butterfly_sequence` | Sends the seven fixed directed transactions with `idle_cycles_before=0` |
| `butterfly_random_sequence` | Generates full-range signed 16-bit constrained-random inputs and checks every `randomize()` call |
| `butterfly_sequencer` | Arbitrates sequence items for the driver |
| `butterfly_driver` | Drives bubbles and valid transactions through `driver_cb` without computing expected results |
| `butterfly_input_monitor` | Publishes only interface transactions actually observed with `rst=0 && valid_in=1` |
| `butterfly_output_monitor` | Publishes `valid_out`, output data, and saturation flags every cycle |
| Independent predictor | Computes expected fixed-point results without calling V0 or the DUT |
| `butterfly_scoreboard` | Checks latency, order, values, flags, counts, and final queue state |
| `butterfly_agent` | Contains the sequencer, driver, and both monitors |
| `butterfly_env` | Connects monitor analysis ports to the scoreboard |
| `butterfly_test` | Runs the directed sequence, then the constrained-random sequence, and drains the pipeline |

`tb/uvm/tb_butterfly_uvm_top.sv` generates the 10 ns clock, applies the initial synchronous reset, instantiates `butterfly_pipe`, supplies the virtual interface through `uvm_config_db`, calls `run_test("butterfly_test")`, and provides a 1 ms hard timeout.

## 4. Stimulus and Bubbles

The directed sequence retains seven explicit smoke transactions and sends them back-to-back. It does not parse the common CSV file.

The constrained-random sequence generates 1,000 transactions by default. `+NUM_RANDOM=<n>` can override this count. Each of `a_re`, `a_im`, `b_re`, `b_im`, `w_re`, and `w_im` is randomized across its full signed 16-bit range.

`idle_cycles_before` is constrained to 0 through 3. Its distribution favors continuous throughput:

| Bubble cycles before a transaction | Intended distribution |
|---:|---:|
| 0 | approximately 70% |
| 1 | approximately 20% |
| 2 or 3 combined | approximately 10% |

A zero gap permits valid transactions on adjacent cycles and preserves `II=1`. During a bubble, the driver holds `valid_in=0`. Bubble cycles are not published by the input monitor and therefore do not create predictor entries or disturb transaction order.

## 5. Observed-Transaction Data Flow

The scoreboard does not trust the driver as proof that a transaction reached the DUT. The path is:

```text
sequence → sequencer → driver → interface
                               ↓
                    input monitor → predictor → expected queue

interface → output monitor → scoreboard comparison
```

The input monitor samples the interface and publishes a transaction only when it actually observes `rst=0 && valid_in=1`. The output monitor publishes an observation every cycle, including cycles with `valid_out=0`, so the scoreboard can detect both a missing valid output and an unexpected valid output.

Driver and monitor clocking blocks use falling-edge events. The driver prepares inputs half a cycle before the DUT rising-edge sample, and the monitors observe stable values after the preceding rising-edge DUT update. This avoids races with nonblocking assignments in the DUT.

## 6. Independent Fixed-Point Predictor

The predictor neither calls nor instantiates `butterfly_comb`, `butterfly_pipe`, or a shared RTL arithmetic helper. It independently implements the numerical contract:

1. calculate `S = A + B` and `D = A - B` with 17-bit signed results;
2. calculate four signed 17-by-16-bit products, retaining each complete 33-bit result;
3. sign-extend the products and calculate the real and imaginary product combinations at 34 bits;
4. convert Q4.30 results to Q1.15 using round-to-nearest, ties-to-even;
5. perform range checking after rounding, then saturate to signed 16-bit Q1.15;
6. calculate `sat_y0_re`, `sat_y0_im`, `sat_y1_re`, and `sat_y1_im` independently.

For RNE, the predictor uses the shifted base, guard bit, sticky bits, and retained least-significant bit. A tie increments only when the retained result is odd. Saturation is evaluated after rounding so that a rounding increment that crosses the Q1.15 boundary is handled correctly.

## 7. Scoreboard Checks

Each transaction published by the input monitor produces one expected item tagged for `input_cycle + 2`. The scoreboard checks:

- assertion of `valid_out` at exactly the required cycle;
- absence of `valid_out` when no transaction is due;
- FIFO output ordering through the expected queue;
- `y0_re`, `y0_im`, `y1_re`, and `y1_im`;
- all four component-level saturation flags;
- equal input and checked-output counts;
- an empty expected queue at the end of simulation.

The output monitor publishes every cycle, which makes bubble placement visible to the latency checker without inserting bubble entries into the predictor.

## 8. Completed XSim Run

The current completed run used Vivado XSim 2025.1 with UVM 1.2.

| Result | Value |
|---|---:|
| Directed transactions | 7 |
| Constrained-random transactions | 1,000 |
| Total transactions | 1,007 |
| Random bubbles | 0 to 3 cycles, approximately 70% / 20% / 10% |
| `inputs` | 1,007 |
| `outputs_checked` | 1,007 |
| `remaining_queue` | 0 |
| `errors` | 0 |
| `UVM_WARNING` | 0 |
| `UVM_ERROR` | 0 |
| `UVM_FATAL` | 0 |
| Normal simulation end | 24,890 ns |

This result confirms that the directed plus constrained-random run passed the implemented predictor, ordering, flag, and two-cycle latency checks for that simulation run.

## 9. Relationship to the Legacy Regression

The existing non-UVM V1 testbench, `tb/v1/tb_butterfly_pipe.sv`, has also been replayed successfully under XSim using all 1,071 Python-generated vectors from `tb/test_vectors/butterfly_common.csv`.

That legacy result is separate from the UVM result. The current UVM sequences ran seven explicit directed transactions and 1,000 newly constrained-random transactions; they did not replay the 1,071 CSV vectors.

## 10. Remaining Verification Work

The following work has not been completed in the current UVM environment:

- a mid-flight reset UVM sequence;
- functional coverage;
- SystemVerilog Assertions (`SVA`);
- UVM replay of the 1,071 CSV vectors;
- multi-seed regression;
- automated command-line regression;
- coverage closure;
- formal verification.

These limitations prevent interpreting one passing random run as exhaustive verification or proof of absolute correctness.
