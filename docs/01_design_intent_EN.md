# Radix-2 Butterfly MVP: Design Intent

## 1. Purpose

This document defines the design objectives, functional boundaries, evaluation methodology, and initial assumptions of the Radix-2 Butterfly MVP.

It explains why the design is structured this way and what the engineering loop is intended to demonstrate. Exact widths, binary-point positions, rounding, and overflow behavior are defined in `02_fixed_point_spec_EN.md`; the microarchitecture is defined in `03_microarchitecture_EN.md`; verification evidence is recorded in `04_verification_plan_EN.md`; and synthesis, place-and-route, and PPA analysis are recorded in `05_synthesis_and_ppa_analysis_EN.md`.

## 2. Project Objective

The project uses a DIF Radix-2 complex Butterfly processing element to complete the following engineering loop:

```math
\text{design intent}
\rightarrow
\text{fixed-point model}
\rightarrow
\text{RTL}
\rightarrow
\text{verification}
\rightarrow
\text{synthesis}
\rightarrow
\text{result analysis}
\rightarrow
\text{design revision}
```

The primary success criterion is not the highest possible maximum clock frequency, `F_max`. The goal is a processing element that is:

- functionally correct;
- behaviorally well specified;
- synthesizable;
- reproducible;
- comparable across implementations;
- supported by verification and synthesis evidence; and
- capable of at least one justified revision based on that evidence.

A higher `F_max` is one metric, not the sole objective. Higher frequency may require more registers, more area, greater cycle latency, greater design and verification complexity, or higher power. The project therefore evaluates tradeoffs instead of assuming that the highest-frequency implementation is always best.

## 3. Functional Definition

The MVP implements a DIF Radix-2 complex Butterfly:

```math
Y_0=A+B
```

```math
Y_1=(A-B)\times W
```

where `A`, `B`, and `W` are complex inputs, `Y_0` and `Y_1` are complex outputs, and `W` is an externally supplied twiddle factor.

Expanded into real components:

```math
Y_{0,\mathrm{re}}=A_{\mathrm{re}}+B_{\mathrm{re}}
```

```math
Y_{0,\mathrm{im}}=A_{\mathrm{im}}+B_{\mathrm{im}}
```

```math
D_{\mathrm{re}}=A_{\mathrm{re}}-B_{\mathrm{re}}
```

```math
D_{\mathrm{im}}=A_{\mathrm{im}}-B_{\mathrm{im}}
```

```math
Y_{1,\mathrm{re}}=D_{\mathrm{re}}W_{\mathrm{re}}-D_{\mathrm{im}}W_{\mathrm{im}}
```

```math
Y_{1,\mathrm{im}}=D_{\mathrm{re}}W_{\mathrm{im}}+D_{\mathrm{im}}W_{\mathrm{re}}
```

Complex values are represented as separate real and imaginary signals. The six scalar inputs are `a_re`, `a_im`, `b_re`, `b_im`, `w_re`, and `w_im`. The four scalar outputs are `y0_re`, `y0_im`, `y1_re`, and `y1_im`.

Each output component has an independent saturation flag: `sat_y0_re`, `sat_y0_im`, `sat_y1_re`, and `sat_y1_im`. The core does not retain a separate aggregate saturation state. A parent block may OR-reduce the appropriate component flags when only a Y0-, Y1-, or transaction-level indication is required.

All values use signed fixed-point representation. Inputs are 16 bits; the exact format and intermediate widths are frozen in the fixed-point specification.

## 4. Frozen Design Decisions

### 4.1 DIF Radix-2

The MVP implements one unambiguous Butterfly dataflow and does not support both DIT and DIF. DIF defines the operation order as:

1. compute `A+B` and `A-B`;
2. multiply `A-B` by `W`.

This order creates natural arithmetic boundaries. V1 is therefore frozen as a three-stage registered implementation: stage 1 performs add/subtract and aligns the twiddle factor, stage 2 performs four parallel real multiplications, and stage 3 performs product combination, rounding, saturation, and output registration. This partition has passed functional verification and an open-source ASIC implementation flow, but it is one valid design point rather than a global optimum.

Radix-2 is not claimed to outperform Radix-4 in every FFT. It is the smallest useful unit that still exposes fixed-point, complex-multiply, pipeline, and resource tradeoffs within the MVP schedule.

### 4.2 Standalone Butterfly Processing Element

The MVP does not implement a complete FFT. A complete FFT would add inter-stage scheduling, address generation, memory organization, twiddle indexing, and controller state. Keeping the Butterfly independent makes it possible to distinguish failures caused by numerical representation, arithmetic RTL, pipeline control, memory, address generation, or FFT-stage scheduling.

### 4.3 Externally Supplied Twiddle Factor

The processing element does not contain a twiddle ROM or a real-time coefficient generator. Adding either would require decisions about FFT size, coefficient count and quantization, address generation, ROM latency, alignment with `A` and `B`, synchronous versus asynchronous reads, and whether arbitrary `W` values remain legal. Those questions bind the PE to a specific FFT system without strengthening the arithmetic datapath loop, so `W` remains an input.

### 4.4 `valid_in/valid_out` Interface

Clocked V1 uses `valid_in` and `valid_out` to mark transactions. It has no `ready` signal or backpressure and assumes the downstream block can always accept a valid output. Combinational V0 has no transaction state and therefore no core `valid`; its synchronous evaluation wrapper adds a valid pipeline for physical comparison.

In this MVP, “streaming” means:

- consecutive transactions are allowed;
- V1 targets an initiation interval of `II=1`, accepting at most one new `A,B,W` tuple per cycle; and
- `valid` is delayed by the same pipeline latency as its data.

It does not mean that a complete streaming FFT is implemented. Backpressure would require pipeline stall, state retention, and restart behavior and would substantially expand the control and verification state space.

### 4.5 Platform-Independent RTL

The RTL does not instantiate vendor primitives or depend on proprietary FPGA interfaces. It uses portable synthesizable SystemVerilog.

The MVP uses an open-source ASIC toolchain for generic synthesis, standard-cell mapping, placement, and routing. V0 and V1 are compared under the same library, constraints, and evaluation boundaries. Tool versions, Nangate45 setup, SDC constraints, implementation flow, and results are documented in `05_synthesis_and_ppa_analysis_EN.md`.

The results are valid only for the stated open-source flow, Nangate45 typical corner, and constraints. Area is post-route design area; timing is STA under the extracted parasitic model; and power is vectorless because no workload VCD/SAIF was supplied. These results support controlled relative comparison, not product signoff or direct projection to another process or workload.

## 5. Microarchitectures Under Comparison

| Version | Structural role | Primary purpose |
|---|---|---|
| V0 | Pure combinational datapath baseline | Establish the simplest functional and combinational baseline |
| V1 | Three-stage fixed-latency pipeline | Measure the effect of explicit stage partitioning on timing, latency, and resources |

Both versions use the same mathematical definition, I/O and fixed-point behavior, four component-level saturation flags, reusable reference model and vectors, synthesis tools, target library, and comparable constraints.

The same 17-column vector set checks four outputs, two compatibility aggregate flags, and four component flags. Functional fairness means identical valid inputs produce bit-identical values and component flags.

Implementation fairness is established by `butterfly_comb_eval` and `butterfly_pipe_eval`. The former adds input and output registers around V0; the latter adds equivalent external boundaries around V1. Internal V1 pipeline registers remain part of its real area, clock-network, and latency cost.

V1 stages are:

1. compute and register `A+B` and `A-B`, while registering the transaction-aligned `W`;
2. compute and register four real products, while delaying the wide `Y_0` sum by one cycle;
3. combine products, round `Y_1`, saturate all four components, and register outputs and flags.

V1 has no `ready`, backpressure, or pipeline stall. Invalid input cycles create bubbles that propagate without compressing transaction spacing. An input accepted at rising edge `t` with `valid_in=1` produces its output at edge `t+2` with `valid_out=1`. Core latency is therefore two cycles and initiation interval is `II=1`.

Any later repartitioning must create a new version rather than silently changing the frozen V1 definition.

## 6. Evaluation Metrics

| Metric | Meaning |
|---|---|
| Functional correctness | Bit-exact agreement with the reference model |
| Maximum clock frequency, `F_max` | Highest estimated operating frequency under a stated flow and constraints |
| Critical path | Actual combinational path limiting clock frequency |
| Cycle latency | Number of clock cycles from input to corresponding output |
| Time latency | Cycle latency multiplied by the operating clock period |
| Initiation interval, `II` | Minimum cycle spacing between accepted transactions |
| Throughput | Accepted input tuples per unit time in steady state |
| Logic resources | Mapped standard cells and reported equivalent resources |
| Register count | Storage required by pipeline and state retention |
| Multiply resources | Library-mapped multiplication logic and implementation cost |
| Design and verification complexity | Added state, corner cases, and verification burden |
| Power | Vectorless versus activity-driven estimates, with explicit evidence limits |

Every comparison must identify which dimensions improve and which regress. Pipelining may raise `F_max` while increasing register count and cycle latency; its value depends on throughput, clock, resource, and interface requirements.

## 7. Explicitly Excluded Scope

The MVP excludes:

- a complete FFT;
- combined DIT/DIF operation;
- Radix-4 or other radix comparisons;
- 4-point, 8-point, or larger FFT networks;
- twiddle ROM or real-time twiddle generation;
- memory-system variants;
- AXI, DMA, or off-chip interfaces;
- `ready`, backpressure, or a stallable pipeline;
- time-multiplexed multipliers or other resource sharing;
- multiple input widths or Q-format comparisons;
- UVM;
- FPGA board validation;
- product-level physical signoff, tapeout, or post-silicon validation;
- exhaustive multi-process, multi-PVT, or multi-seed closure;
- workload-level power claims without real activity; and
- presenting Nangate45 results as commercial-process PPA.

These may become future work but must not be added before the MVP loop is closed.

## 8. MVP Acceptance Criteria

### 8.1 Specification and Model

- The DIF Radix-2 mathematical definition is explicit.
- Fixed-point formats, width propagation, rounding, and overflow behavior have an independent specification.
- A bit-exact reference model exists.
- Model and RTL outputs are compared automatically.

### 8.2 RTL and Verification

- V0 and V1 are synthesizable.
- They are functionally equivalent and differ only in timing and microarchitecture.
- Directed, boundary, overflow, random, continuous-valid, bubble, and reset scenarios are covered.
- `valid_out` is aligned with the corresponding data.
- The environment reports pass or fail automatically.

### 8.3 Synthesis and Comparison

- Both versions complete synthesis and place-and-route under comparable conditions.
- Area, timing, power, critical-path, and electrical-violation reports are retained.
- Highest tested passing point, latency, `II`, throughput, area, and register cost are compared.
- Tool, library, constraint, and power-activity assumptions accompany every result.
- Typical-corner open-source results are not described as signoff PPA or absolute `F_max`.

### 8.4 Engineering Loop

- Pre-synthesis critical-path and pipeline hypotheses are recorded.
- Post-synthesis analysis separates supported from rejected hypotheses.
- At least one small evidence-driven modification is completed.
- Verification and synthesis are rerun after modification.
- Benefits, costs, and unresolved issues are recorded.

## 9. Decisions Delegated to Later Documents

Later specifications or implementation work determine the exact code organization of rounding and saturation logic, whether to add real VCD/SAIF activity, additional seeds or PVT corners, and whether current evidence justifies a V2 architecture.

Numerical behavior belongs in `02_fixed_point_spec_EN.md`; microarchitecture and interface timing in `03_microarchitecture_EN.md`; verification closure in `04_verification_plan_EN.md`; and tools, constraints, and results in `05_synthesis_and_ppa_analysis_EN.md`.

## 10. Initial Assumptions and Questions

### 10.1 Established Engineering Facts

- The exact sum or difference of two signed `N`-bit values may require `N+1` bits.
- Pipeline registers split combinational paths but add state and cycle latency.
- Mapping, physical implementation, and timing depend on tools, libraries, constraints, and strategy.
- `F_max`, latency, and throughput are distinct metrics.

### 10.2 Judgments Supported by Current Experiments

- Frozen three-stage V1 effectively splits V0's long combinational path.
- Because both versions support `II=1`, V1's throughput gain comes from higher reachable frequency, not more transactions per cycle.
- The gain costs pipeline registers, clock-network area, and cycle latency.
- Current vectorless power estimates favor V1, but do not prove real FFT workload power.

Exact values and applicability conditions are defined in `05_synthesis_and_ppa_analysis_EN.md`.

### 10.3 Questions the Analysis Must Answer

1. Which arithmetic nodes lie on the actual worst setup paths of V0 and V1?
2. Does the power ranking remain after common VCD/SAIF activity is supplied?
3. Are area and frequency gains stable across seeds, PVT corners, or libraries?
4. Does the `F_max` gain justify additional registers, latency, and complexity?
5. Would the selected architecture remain appropriate under lower-area, lower-latency, or lower-power objectives?
6. Which conclusions are specific to the current Nangate45 setup and cannot be generalized to a product?

## 11. Design-Intent Summary

The objective is not “the highest-frequency Butterfly.” It is a bounded DIF Radix-2 complex Butterfly that completes a verifiable, synthesizable, comparable, and revisable digital-design loop.

By excluding a complete FFT, twiddle storage, backpressure, resource sharing, and platform-specific implementation, the project remains focused on how mathematics becomes fixed-point RTL, how width and numerical policy affect correctness and resources, how physical critical paths determine pipeline boundaries, how frequency/latency/throughput/resources trade off, and how synthesis evidence feeds back into design judgment.

The final value is the ability to explain what the design solves, why it was selected, whether evidence supports the original assumptions, and how the architecture should change when the objective changes.
