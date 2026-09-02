# Radix-2 Butterfly MVP: Synthesis and PPA Analysis

## 1. Purpose

This document records synthesis, technology mapping, place-and-route, and preliminary PPA comparison for combinational V0 and pipelined V1, and explains the observed architectural tradeoffs.

It distinguishes tool-reported data, derived metrics, and interpretations that require activity files or further experiments. Nangate45 and the open-source physical flow support controlled architectural comparison, not commercial signoff or measured silicon claims.

## 2. Compared Designs

### 2.1 Cores

| Version | Structure | Fixed core latency | II |
|---|---|---:|---:|
| V0 | Combinational Butterfly | 0 core cycles | 1 through synchronous wrapper sampling |
| V1 | Registered add/subtract, multiply, combine/quantize stages | 2 cycles from input sampling edge to output-valid edge | 1 |

Both implement the same DIF Radix-2 function, Q1.15 I/O, RNE, saturation policy, and four component flags.

### 2.2 Fair Evaluation Wrappers

`butterfly_comb_eval` and `butterfly_pipe_eval` add equivalent external input/output register boundaries. They standardize clock, reset, valid, input load, and output load while making arithmetic paths register-to-register.

At wrapper level, V0 latency is one cycle, V1 latency is four cycles, and both have `II=1`. The wrappers establish physical comparison boundaries and do not redefine core latency.

## 3. Tool and Process Environment

| Item | Configuration |
|---|---|
| RTL simulation | Verilator 5.032 |
| Local generic synthesis | Yosys 0.52 |
| ORFS synthesis | Yosys 0.68+post |
| Physical implementation | OpenROAD 26Q3-1305-gf552262465 |
| Container | `openroad/orfs:latest`, image digest recorded at runtime |
| Platform | Nangate45 |
| Timing library | `NangateOpenCellLibrary_typical.lib` |
| Nominal voltage | 1.10 V |
| Floorplan target | Common utilization, aspect-ratio, and density settings |

Generic synthesis explains inferred operators, registers, and hierarchy. Area, timing, and power in this document come from mapped and routed ORFS results.

## 4. Constraints

### 4.1 Common Constraints

At every common-frequency point, both versions use one `core_clock`; 2.000 ns at 500 MHz or 2.500 ns at 400 MHz; 0.050 ns uncertainty and clock transition; input and output delays equal to 10% of the period; 0.050 ns input transition; 0.010 output load; and synchronous reset excluded from performance paths.

### 4.2 Experiment Types

| Experiment | Question |
|---|---|
| Common 400 MHz | When both meet the same throughput target, what are the area, margin, and estimated-power costs? |
| Common 500 MHz | Does pipelining reach a target that V0 cannot? |
| Frequency scan | What is each version's highest fully routed point passing final STA in the tested set? |

An unclosed V0 at 500 MHz must not represent normal operating-point area, and power at two different peak frequencies is not a same-frequency power comparison.

## 5. Generic Synthesis Observations

Yosys reports approximately 42 abstract cells for full V0 hierarchy and 67 for V1. V1 introduces enabled/synchronously reset sequential cells and about 337 retained register bits. Multiply and core add/subtract structures remain broadly similar; V1's principal structural increment is pipeline state and valid control.

Abstract cell count is not physical area. Multipliers, adders, muxes, and flops have different areas, and mapping is affected by the target library, constraints, buffering, and physical optimization.

## 6. Common 400 MHz Comparison

### 6.1 Final Data

| Metric | V0 | V1 | V1 change |
|---|---:|---:|---:|
| Period | 2.500 ns | 2.500 ns | Same |
| Worst setup slack | +0.05 ns | +0.82 ns | +0.77 ns |
| TNS | 0.00 ns | 0.00 ns | Both pass |
| Implementation-derived Fmax | 408.99 MHz | 594.16 MHz | +45.3% |
| Standard-cell design area | 11,051 μm² | 12,859 μm² | +16.4% |
| Reported utilization | 51% | 51% | Same |
| Vectorless power | 0.304 W | 0.122 W | -59.9% |
| II | 1 | 1 | Same |
| Throughput | 400 Mops/s | 400 Mops/s | Same |

At a common passing point, V1 costs about 16.4% more area and has substantially more timing margin.

### 6.2 Cell Composition

| Cell type | V0 | V1 |
|---|---:|---:|
| Clock buffers | 17 | 116 |
| Timing-repair buffers | 418 | 238 |
| Sequential cells | 166 | 503 |
| Multi-input combinational cells | 4403 | 4707 |

Pipelining adds 337 sequential cells and a larger clock tree, but reduces the buffering required to repair long paths. Final area is not simply V0 area plus pipeline-register area.

### 6.3 Power Composition

| Category | V0 | V1 |
|---|---:|---:|
| Sequential | 1.01 mW | 3.32 mW |
| Combinational | 302 mW | 118 mW |
| Clock | 0.368 mW | 1.01 mW |
| Total | 304 mW | 122 mW |

The tool includes V1's greater register and clock power. Lower total power is driven by the combinational estimate. One report-consistent but unproven explanation is that V0 permits glitches to propagate through a long add/multiply/combine/quantize chain while V1 registers cut transient propagation. Without common VCD/SAIF activity, this remains a hypothesis.

### 6.4 Estimated Energy per Operation

At 400 MHz and `II=1`:

| Design | Vectorless estimated energy |
|---|---:|
| V0 | 0.760 nJ/op |
| V1 | 0.305 nJ/op |

These are derived from default activity assumptions only.

## 7. Common 500 MHz Comparison

### 7.1 Timing

| Metric | V0 | V1 |
|---|---:|---:|
| Target period | 2.000 ns | 2.000 ns |
| Worst setup slack | -0.26 ns | +0.36 ns |
| TNS | -8.37 ns | 0.00 ns |
| Implementation-derived Fmax | 441.74 MHz | 610.81 MHz |
| Max slew/fanout/cap violations | 0/0/0 | 0/0/0 |

V0 completes the flow but fails 500 MHz. V1 passes with 0.36 ns setup margin, demonstrating that pipelining reaches a target the baseline cannot.

### 7.2 Area and Power

| Metric | V0 | V1 | V1 change |
|---|---:|---:|---:|
| Design area | 12,474 μm² | 12,872 μm² | +3.2% |
| Utilization | 58% | 51% | Different automatic floorplans |
| Vectorless power | 0.493 W | 0.147 W | -70.2% |

V0 receives 1,430 timing-repair buffers while V1 needs 248. That failed-target repair cost masks most pipeline-register area, so 3.2% is not the normal pipeline premium; use the 400 MHz 16.4% comparison.

### 7.3 IR-Drop Observation

| Metric | V0 | V1 |
|---|---:|---:|
| Worst VDD drop | 0.496 V | 0.120 V |
| Worst VDD percentage drop | 45.08% | 10.89% |
| Worst VDD voltage | 0.604 V | 0.980 V |

V0 would be unacceptable in a real design and V1 also needs improvement. However, this uses an automatic educational PDN, vectorless power, and non-IR-aware final STA. These values expose pressure under default assumptions; they are not signoff integrity results.

## 8. Highest Tested Passing Frequencies

### 8.1 Scan Results

| Design | Highest complete passing point | Worst setup | Worst hold | Peak throughput |
|---|---:|---:|---:|---:|
| V0 | 425 MHz | +0.02 ns | +0.06 ns | 425 Mops/s |
| V1 | 640 MHz | +0.03 ns | +0.02 ns | 640 Mops/s |

Both have final TNS=0 and no max-transition, fanout, or capacitance violations. Because both have `II=1`, the 50.6% tested frequency gain translates directly into steady-state throughput. These are the highest passing integer points in the current scan, not absolute Fmax.

### 8.2 Peak Implementation Cost

| Metric | V0 @ 425 MHz | V1 @ 640 MHz | V1 change |
|---|---:|---:|---:|
| Design area | 11,343 μm² | 13,116 μm² | +15.6% |
| Utilization | 52% | 52% | Same |
| Clock buffers | 17 | 114 | +97 |
| Timing-repair buffers | 572 | 503 | -69 |
| Sequential cells | 166 | 503 | +337 |
| Multi-input combinational cells | 4405 | 4707 | +302 |
| Vectorless power | 0.361 W | 0.191 W | -47.1% |

The frequencies differ, so peak-point power is not a same-frequency comparison.

### 8.3 Derived Peak Metrics

| Metric | V0 | V1 | Change |
|---|---:|---:|---:|
| Vectorless energy | 0.849 nJ/op | 0.298 nJ/op | -64.9% |
| Throughput/design area | 0.0375 Mops/s/μm² | 0.0488 Mops/s/μm² | +30.2% |

These depend on the current power model and tested points and must retain those qualifiers.

### 8.4 Post-Route Physical Critical-Path Inspection

The final `6_final.odb`, SDC, and extracted SPEF were loaded together in OpenROAD GUI. Higher-precision timing values are:

| Design | Startpoint | Endpoint | Arrival | Required | Setup slack |
|---|---|---|---:|---:|---:|
| V0 @ 425 MHz | `a_im_q[1]$_DFFE_PP_` | `y1_re[8]$_SDFFCE_PN1P_` | 2.374 ns | 2.397 ns | +0.023 ns |
| V1 @ 640 MHz | `u_core.diff_re_s1[6]$_DFFE_PP_` | `u_core.m2_s2[31]$_DFFE_PP_` | 1.610 ns | 1.643 ns | +0.033 ns |

The two-decimal text values describe the same results. Final slack should be taken from the tool, not reconstructed from individually rounded display fields.

#### V0: Full Y1 Chain

![V0 425 MHz post-route critical path](images/V0_425MHz_endpoint_register.png)

The path runs from a wrapper input register to the `y1_re` output register through HA, FA, AOI/OAI, mux, and buffer cells consistent with difference, multiplication, wide combination, rounding, and saturation. It crosses several placement regions, but visual length alone cannot prove wire delay dominates.

#### V1: Stage-2 Multiplier

![V1 640 MHz post-route critical path](images/V1_640MHz_endpoint_register.png)

The path is bounded by adjacent `diff_re_s1` and `m2_s2` pipeline registers. A high-fanout source bit is buffered before driving multiplier partial-product logic, then passes through HA/FA reduction into the product register. This physically supports the 17×16 signed multiplier as the current limiting stage.

## 9. Latency, Throughput, and Area Tradeoff

| Dimension | V0 | V1 |
|---|---|---|
| II | 1 | 1 |
| Wrapper latency | 1 cycle | 4 cycles |
| Single-transaction response | Shorter | Longer |
| Highest tested throughput | 425 Mops/s | 640 Mops/s |
| 400 MHz area | 11,051 μm² | 12,859 μm² |

V1 trades greater fixed latency, more registers, and a larger clock tree for shorter paths, higher tested frequency, and greater steady-state throughput. The correct choice depends on system requirements.

## 10. Tool Compatibility and Workarounds

### 10.1 SystemVerilog Netlist `signed` Parsing

The mapped Yosys netlist retained `signed`/`unsigned` port modifiers rejected by the current OpenROAD STA Verilog parser. Only those modifiers were removed from the already-mapped gate netlist before continuing. Source RTL and completed signed-arithmetic mapping were unchanged, but no independent LEC was completed; this is a compatibility workaround, not formal proof.

### 10.2 SDC Compatibility

The current OpenSTA does not support `remove_from_collection`, so inputs were listed explicitly:

```tcl
set data_inputs [get_ports {valid_in a_re a_im b_re b_im w_re w_im}]
```

This preserves constraint intent without an unsupported collection operation.

### 10.3 CTS `repair_timing` Native Crash

At V0 425 MHz and V1 640 MHz, CTS `repair_timing` reproducibly exited with `illegal instruction` after setup/hold repair. Thread count, LEC, last-gasp repair, gate cloning, and pin swapping were excluded as individual causes.

Peak runs used:

```text
SKIP_CTS_REPAIR_TIMING=1
```

Repair was deferred to later stages. Final reports show passing setup/hold, TNS=0, and zero electrical violations. Common 400/500 MHz runs used the standard flow. This condition must accompany peak-point claims.

## 11. Conclusions

### 11.1 Supported by Data

- Both versions complete an open-source RTL-to-route ASIC flow.
- At 400 MHz, V1 gains substantial margin for about 16.4% area.
- At 500 MHz, V0 fails and V1 passes.
- The highest tested passing point increases from 425 to 640 MHz.
- With equal `II=1`, tested peak throughput rises about 50.6%.
- V1 adds pipeline/clock cost but reduces timing-repair pressure.
- Final physical inspection confirms V0's full Y1 path and V1's stage-2 multiplier path.
- V1 contains high-fanout data buffering and HA/FA partial-product reduction; splitting stage 3 cannot shorten the current path.
- Vectorless estimates rank V1 combinational power lower at all tested points.

### 11.2 Hypotheses or Limited Evidence

- Real activity has not proven that pipeline registers reduce power mainly by blocking glitches.
- Vectorless power does not represent an FFT workload.
- Automatic-PDN IR-drop does not establish product integrity.
- 425 and 640 MHz are tested points, not absolute Fmax.

Further proof would require common VCD/SAIF, more seeds, formal equivalence, or commercial signoff flows.

## 12. Future Work

Implementation, verification, PPA, and physical critical-path inspection are closed for this MVP. Optional work depends on a new objective:

1. use common VCD/SAIF to strengthen power conclusions;
2. add formal equivalence or gate-level simulation;
3. pipeline or replace the stage-2 multiplier if higher frequency is required; or
4. stop chasing marginal MHz and move system-complexity training to the independent Systolic Array project.
