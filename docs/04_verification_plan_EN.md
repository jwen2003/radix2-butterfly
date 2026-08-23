# Radix-2 Butterfly MVP: Verification Plan

## 1. Purpose

This document defines the functional-verification objectives, reference model, test environment, scenario matrix, pass criteria, current evidence, and remaining gaps for the Radix-2 Butterfly MVP.

Verification must demonstrate that combinational V0 and pipelined V1 produce bit-identical numerical results and component-level saturation flags for the same valid inputs under one fixed-point contract. V1 must additionally satisfy fixed latency, initiation interval, bubble propagation, and reset-discard semantics.

Simulation success is not treated as formal proof, and the current vector count is not exhaustive coverage. Synthesis, timing, and physical results are documented in `05_synthesis_and_ppa_analysis_EN.md`.

## 2. Scope

### 2.1 Verification Targets

| Target | Responsibility | Verification focus |
|---|---|---|
| `sat_q15` | Saturate a wide signed integer to 16-bit Q1.15 | Positive/negative boundaries, in-range values, component flag |
| `rne_sat_q30_to_q15` | RNE Q*.30 to Q1.15 and saturate | guard/sticky, ties-to-even, signed symmetry, post-round saturation |
| `butterfly_comb` | V0 combinational Butterfly | Four outputs, four component flags, deterministic combinational behavior |
| `butterfly_pipe` | V1 fixed-latency Butterfly | V0 numerical equivalence, two-cycle core latency, II=1, bubbles, reset |
| Evaluation wrappers | Common registered boundaries for physical comparison | Preserve numerical behavior; synthesis/PPA only, not a replacement for core verification |

### 2.2 Explicit Exclusions

- `ready`, backpressure, and stallable pipelines;
- complete FFT memory, addressing, and stage scheduling;
- multiple clock domains and asynchronous reset;
- UVM;
- FPGA or post-silicon testing;
- exhaustive input-space enumeration;
- formal equivalence and property proof; and
- workload-activity power verification.

## 3. Verification Authority

Conflicts are resolved in this order:

1. `01_design_intent_EN.md` defines functional scope and interface intent.
2. `02_fixed_point_spec_EN.md` defines numerical values, widths, rounding, and saturation.
3. `03_microarchitecture_EN.md` defines pipeline, valid, and reset timing.
4. The Python bit-exact model implements the numerical contract.
5. SystemVerilog testbenches compare RTL against model-generated expectations.

Any conflict must be fixed in the specification or implementation before vectors are regenerated and regression is rerun. Testbench comparisons must not be weakened to hide a mismatch.

## 4. Reference Model

### 4.1 Principles

`model/fixed_point_model.py` is a timing-free bit-exact integer model. All public inputs and outputs are signed 16-bit Q1.15 encodings.

It:

1. computes `A+B` and `A-B` with 17-bit meaning;
2. saturates both Y0 components independently to Q1.15;
3. computes four real products and 34-bit complex combinations;
4. applies round-to-nearest, ties-to-even to each Y1 component before saturation;
5. emits `sat_y0_re`, `sat_y0_im`, `sat_y1_re`, and `sat_y1_im`; and
6. derives aggregate compatibility flags only by OR-reducing component flags.

### 4.2 Model Self-Checks

- Inputs must remain in `[-32768, 32767]`.
- The Butterfly datapath must not use floating-point arithmetic.
- Positive and negative ties-to-even behavior must be symmetric.
- Rounding precedes saturation.
- Complex-combination results must satisfy the specified wide-range assertions.
- Random vectors use a fixed seed.

## 5. Test Vectors

### 5.1 Common Set

V0 and V1 use one CSV dataset:

| Category | Count | Purpose |
|---|---:|---|
| Directed | 7 | Zero, pass-through, equal inputs, saturation, extrema, mixed signs |
| Twiddle | 64 | Quantized unit-circle coefficients across quadrants and sign combinations |
| Fixed-seed random | 1000 | Broader data and component-saturation combinations |
| Total | 1071 | Common V0/V1 numerical regression |

The default seed is `0xB077E2`. The generation command, seed, and CSV schema must be retained whenever vectors are regenerated.

### 5.2 CSV Contract

The common CSV contains a case name, six input components, four expected output components, two compatibility aggregate saturation flags, and four component saturation flags. Component flags are the primary checks; aggregate flags are independently checked against their OR reductions.

### 5.3 Required Numerical Scenarios

| Scenario | Expected check |
|---|---|
| All zeros | All values and flags are zero |
| `A=B` | Difference and Y1 are zero; Y0 follows the specification |
| Zero real or imaginary twiddle component | Correct cross terms and signs |
| Maximum/minimum Q1.15 encodings | No unsigned interpretation or truncation wrap |
| Positive/negative Y0 saturation | Clamp to 32767/-32768; only the affected component flag asserts |
| Positive/negative Y1 saturation | Round first, then compare the wide result |
| Below half, exact half, above half | Correct RNE increment decision |
| Even/odd retained LSB at a tie | No increment for even, increment for odd |
| Negative ties-to-even | Round magnitude and restore sign symmetrically |
| Different four-component saturation patterns | Independent flags and correct aggregate reductions |

## 6. V0 Environment

`tb/v0/tb_butterfly_comb.sv` is a file-driven self-checking testbench. For each CSV case it drives six inputs, waits for combinational settling, compares four outputs, compares four component flags, checks both aggregate reductions, accumulates errors, and reports PASS or FAIL at the end.

Requirements:

- use strict four-state comparison;
- fail on empty, malformed, or unparseable CSV files;
- fail on any value or flag mismatch; and
- fail if no vector executes.

## 7. V1 Environment

`tb/v1/tb_butterfly_pipe.sv` uses the same CSV expectations plus a two-slot scoreboard for the core's two-cycle fixed latency.

### 7.1 Latency and Valid

A transaction accepted at rising edge `t` with `valid_in=1` must appear after edge `t+2` with `valid_out=1`.

Checks include:

- exact transaction alignment;
- continuous valid output after pipeline fill under continuous input;
- $II=1$ acceptance;
- bubble propagation without transaction reordering or compression; and
- alignment of $W$ with its corresponding data.

### 7.2 Bubble Behavior

When `valid_out=0`:

- all four saturation flags are zero;
- after the first valid output, data outputs retain the most recent valid values; and
- invalid data contents are ignored but must not disturb later alignment.

The common stream inserts a bubble before every eleventh valid vector to cover both uninterrupted and interrupted traffic.

### 7.3 Reset Behavior

Reset is synchronous. Verification checks that:

- a reset edge clears all pipeline valid state;
- in-flight transactions are discarded and never emerge after release;
- `valid_out=0` during reset;
- all saturation flags are zero during reset;
- data registers need not all clear, but are never treated as transactions without valid;
- the first cycle after release may immediately accept a transaction; and
- pre-reset and post-reset transactions never mix.

The testbench asserts reset while two valid transactions are in flight and sends a new transaction on the first cycle after release.

## 8. Regression Flow

Recommended reproducible order:

1. run Python model unit tests or minimum self-checks;
2. generate the common CSV with fixed parameters;
3. compile and run V0;
4. compile and run V1;
5. retain tool versions, commands, and PASS summaries; and
6. rerun all steps after any RTL, model, specification, or generator change.

The simulation baseline is Verilator 5.032. Testbenches avoid the unsupported `$fscanf` scanset syntax, use `$fgets` plus manual case-name separation, and avoid ordinary comments beginning with `verilator`, which may be misread as tool directives.

## 9. Pass Criteria

### 9.1 Functional

- V0 passes all 1071 vectors with no value or flag mismatches.
- V1 passes the same 1071 vectors with no mismatches.
- Both versions produce identical values and component flags.
- CSV parsing, path, and vector-count checks pass.

### 9.2 Timing Semantics

- V1 core latency is exactly two cycles.
- Consecutive transactions move at $II=1$ without reordering.
- Bubbles propagate cycle by cycle.
- Reset discards every in-flight transaction.
- A new transaction may be accepted immediately after reset release.
- Invalid-output saturation flags are zero and data-retention behavior matches the contract.

### 9.3 Failure Conditions

Any output or flag mismatch, early/late/missing `valid_out`, transaction or twiddle misalignment, discarded transaction emerging after reset, silent pass on empty/malformed/zero-vector input, or unhandled warning under warning-as-error compilation is a failure.

## 10. Current Evidence

- The common dataset contains 1071 reproducible vectors.
- V0 reports `PASS: 1071 vectors checked with no mismatches`.
- V1 passes the same numerical set plus latency, continuous-flow, bubble, component-flag, and reset checks.
- Verilator 5.032 timescale, unused-signal, and CSV scanset compatibility issues have been removed.
- Both versions pass generic Yosys synthesis without inferred latches.
- Both complete Nangate45 mapping and place-and-route, demonstrating use of a synthesizable RTL subset.

This evidence supports correctness within the current regression scope but is not a proof over all states and inputs.

## 11. Remaining Gaps

| Gap | Risk | Priority |
|---|---|---|
| No code/branch/toggle coverage | RTL structural coverage is unquantified | Medium |
| No independent RNE-helper unit regression | Rounding is covered mainly through system vectors | High |
| No formal equivalence | All-input V0/V1 equivalence is unproved | Medium |
| No gate-level simulation | Reset/valid behavior is not dynamically rechecked on the netlist | Low |
| No X/Z injection | Unknown-state robustness is unevaluated | Low |
| No common VCD/SAIF | Power remains vectorless | High if power claims continue |

The MVP may close with these gaps disclosed. If it evolves into a buffered, backpressured Butterfly Engine, its protocol, stall, full/empty, drain, and completion-state verification must be redesigned rather than inherited from this plan.
