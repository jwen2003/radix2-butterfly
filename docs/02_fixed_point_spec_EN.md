# Radix-2 Butterfly MVP: Fixed-Point Specification

## 1. Purpose

This document freezes the fixed-point formats, width propagation, rounding, saturation, and saturation-flag behavior of the Radix-2 Butterfly MVP. It is the numerical contract shared by the Python bit-exact reference model, SystemVerilog RTL, and testbenches.

It does not define pipeline stages, register placement, evaluation wrappers, or target-process implementation. Every microarchitecture must obey this same contract and produce bit-identical outputs and flags for identical inputs, apart from latency. Protocol details are in `03_microarchitecture_EN.md`, verification in `04_verification_plan_EN.md`, and implementation results in `05_synthesis_and_ppa_analysis_EN.md`.

## 2. Mathematical Definition

```math
Y_0=A+B
```

```math
Y_1=(A-B)W
```

Expanded into real arithmetic:

```math
Y_{0,\mathrm{re}}=A_{\mathrm{re}}+B_{\mathrm{re}},\qquad
Y_{0,\mathrm{im}}=A_{\mathrm{im}}+B_{\mathrm{im}}
```

```math
D_{\mathrm{re}}=A_{\mathrm{re}}-B_{\mathrm{re}},\qquad
D_{\mathrm{im}}=A_{\mathrm{im}}-B_{\mathrm{im}}
```

```math
P_{\mathrm{re}}=D_{\mathrm{re}}W_{\mathrm{re}}-D_{\mathrm{im}}W_{\mathrm{im}}
```

```math
P_{\mathrm{im}}=D_{\mathrm{re}}W_{\mathrm{im}}+D_{\mathrm{im}}W_{\mathrm{re}}
```

The final outputs are quantized versions of `Y_0` and `P`. Hereafter, `P_re` and `P_im` denote the wide complex-product results before rounding and saturation.

## 3. Q-Format Convention

`Qm.n` uses `m` integer-side bits including the sign bit and `n` fractional bits, for a total width of `m+n`.

For 16-bit Q1.15:

```math
X=X_{\mathrm{int}}2^{-15}
```

```math
-32768\le X_{\mathrm{int}}\le32767
```

```math
-1\le X\le1-2^{-15}
```

No physical binary point is stored. Q format is an interpretation of a two's-complement bit vector. Extending the integer side does not move the binary point relative to the LSB or change the quantization step.

## 4. Input and Output Formats

Every real and imaginary component is an independent signed two's-complement signal.

| Signal | Width | Format | Step | Range |
|---|---:|---|---:|---|
| `a_re`, `a_im` | 16 | Q1.15 | `2^-15` | `[-1, 1 - 2^-15]` |
| `b_re`, `b_im` | 16 | Q1.15 | `2^-15` | `[-1, 1 - 2^-15]` |
| `w_re`, `w_im` | 16 | Q1.15 | `2^-15` | `[-1, 1 - 2^-15]` |
| `y0_re`, `y0_im` | 16 | Q1.15 | `2^-15` | `[-1, 1 - 2^-15]` |
| `y1_re`, `y1_im` | 16 | Q1.15 | `2^-15` | `[-1, 1 - 2^-15]` |

### 4.1 Twiddle-Factor Constraint

The datapath accepts any legal 16-bit Q1.15 complex `W` and does not check `|W| = 1` in hardware. Normal FFT tests use quantized unit-circle coefficients; robustness and boundary tests may use other legal encodings.

Q1.15 represents `-1` exactly but not `+1`. A quantized twiddle therefore need not have exact unit magnitude, and width safety must not rely on that assumption.

## 5. Width Propagation

### 5.1 Addition and Subtraction

The full sum or difference of two signed 16-bit values generally requires 17 bits. Because both inputs have 15 fractional bits, the result is Q2.15.

For `S=A+B`:

```math
-65536\le S_{\mathrm{int}}\le65534
```

For `D=A-B`:

```math
-65535\le D_{\mathrm{int}}\le65535
```

The step remains `2^-15`: the extension increases dynamic range, not fractional precision.

### 5.2 Individual Real Product

`D` is 17-bit Q2.15 and `W` is 16-bit Q1.15. A full product uses 33 bits and 30 fractional bits:

```math
17+16=33\ \text{bits},\qquad 15+15=30
```

Each product is stored as 33-bit Q3.30:

```math
P=P_{\mathrm{int}}2^{-30}
```

The four products are:

```math
M_0=D_{\mathrm{re}}W_{\mathrm{re}},\quad
M_1=D_{\mathrm{im}}W_{\mathrm{im}},\quad
M_2=D_{\mathrm{re}}W_{\mathrm{im}},\quad
M_3=D_{\mathrm{im}}W_{\mathrm{re}}
```

### 5.3 Complex Product Combination

Two arbitrary 33-bit signed values generally require 34 bits when added or subtracted. The products in this design are constrained by input ranges:

```math
|D_{\mathrm{int}}|\le65535,\qquad |W_{\mathrm{int}}|\le32768
```

```math
|D_{\mathrm{int}}W_{\mathrm{int}}|\le65535\times32768=2147450880
```

```math
|M_i\pm M_j|\le4294901760
```

The signed 33-bit range is:

```math
-4294967296\le x\le4294967295
```

Thus the mathematical result remains within 33 signed bits for the stated inputs. Nevertheless, the RTL does not narrow early based on that proof. Both 33-bit products are explicitly sign-extended to 34 bits before addition/subtraction. `P_re` and `P_im` remain 34-bit Q4.30 until rounding and saturation. This avoids unsafe narrowing and keeps the rule independent of special input constraints.

### 5.4 Summary

| Node | Width | Format | Integer range or constraint |
|---|---:|---|---|
| Input component `A,B,W` | 16 | Q1.15 | `[-32768,32767]` |
| `S=A+B` | 17 | Q2.15 | `[-65536,65534]` |
| `D=A-B` | 17 | Q2.15 | `[-65535,65535]` |
| Individual `D × W` | 33 | Q3.30 | Constrained by actual `D,W` ranges |
| `P_re,P_im` | 34 | Q4.30 | Add/subtract after explicit 34-bit extension |
| Final component | 16 | Q1.15 | `[-32768,32767]` |

## 6. Output Quantization

All four outputs are 16-bit Q1.15. The common policy is:

- round-to-nearest, ties-to-even (RNE);
- saturate rather than wrap; and
- perform required rounding first, then range checking, then saturation.

### 6.1 Y0 Quantization

`Y_0=A+B` is 17-bit Q2.15 and has the same 15 fractional bits as the output. No fractional bits are removed and no rounding is required.

For each component:

```math
Q_{Y_0}=S_{\mathrm{int}}
```

```math
Y_{0,\mathrm{int}}=
\begin{cases}
32767,&Q_{Y_0}>32767\\
-32768,&Q_{Y_0}<-32768\\
Q_{Y_0},&\text{otherwise}
\end{cases}
```

### 6.2 Y1 Round-to-Nearest, Ties-to-Even

`P` is Q4.30 and must lose 15 fractional bits to become Q1.15:

```math
Q_{Y_1}=\operatorname{RNE}\left(\frac{P_{\mathrm{int}}}{2^{15}}\right)
```

For an unambiguous sign-symmetric mathematical definition, let:

```math
M=|P_{\mathrm{int}}|,\qquad
Q_0=\left\lfloor\frac{M}{2^{15}}\right\rfloor,\qquad
R=M\bmod2^{15}
```

The increment condition is:

```math
I=(R>2^{14})\lor(R=2^{14}\land Q_0\text{ is odd})
```

The rounded signed integer is:

```math
Q_{Y_1}=\operatorname{sign}(P_{\mathrm{int}})(Q_0+I)
```

For `P_int=0`, `Q_Y_1=0`.

| Discarded fraction | Behavior |
|---|---|
| Less than half a target LSB | Keep `Q_0` |
| Greater than half a target LSB | Increment away from zero in magnitude |
| Exactly half | Increment only when `Q_0` is odd, making the result LSB even |

Any magnitude-based implementation must use sufficient extension to avoid overflow when negating the minimum two's-complement value. The RTL instead uses an equivalent two's-complement test: `guard` is the highest discarded bit, `sticky` is the OR reduction of the remaining discarded bits, and `kept_lsb` is the lowest retained bit. It increments the signed arithmetic-shift base when `guard && (sticky || kept_lsb)`. This implements ties-to-even for both signs.

### 6.3 Y1 Saturation

After rounding, each component is saturated independently:

```math
Y_{1,\mathrm{int}}=
\begin{cases}
32767,&Q_{Y_1}>32767\\
-32768,&Q_{Y_1}<-32768\\
Q_{Y_1},&\text{otherwise}
\end{cases}
```

Range checking follows rounding because a rounding increment can move a boundary-adjacent wide result out of range.

## 7. Saturation Versus Wraparound

Saturation clamps to the nearest representable limit:

```math
Y_{\max}=32767=1-2^{-15},\qquad Y_{\min}=-32768=-1
```

Wraparound discards high bits and reinterprets the remaining low 16 bits, for example `32767 + 1 -> -32768`. A small overflow can therefore become a large opposite-sign error. The MVP forbids low-16-bit truncation as overflow handling. Saturation does not eliminate overload but makes it bounded and observable.

## 8. Saturation Flags

The module emits four transaction-aligned component flags:

- `sat_y0_re` for actual clamping of `y0_re`;
- `sat_y0_im` for actual clamping of `y0_im`;
- `sat_y1_re` for actual clamping of `y1_re`; and
- `sat_y1_im` for actual clamping of `y1_im`.

Optional aggregate compatibility information is derived combinationally:

```math
\texttt{y0\_sat}=\texttt{sat\_y0\_re}\lor\texttt{sat\_y0\_im}
```

```math
\texttt{y1\_sat}=\texttt{sat\_y1\_re}\lor\texttt{sat\_y1\_im}
```

```math
\texttt{sat\_any}=\texttt{sat\_y0\_re}\lor\texttt{sat\_y0\_im}\lor\texttt{sat\_y1\_re}\lor\texttt{sat\_y1\_im}
```

These are derived values, not independent core state. Y1 flags are evaluated from rounded `Q_Y_1`.

Flags must remain clear when an unclamped result is exactly `0x7FFF` or `0x8000`, or when a wide Y1 value near the numerical boundary still rounds to an in-range encoding. A flag means “the rounded result was out of range and was clamped,” not general precision loss or proximity to a boundary.

Flags have no transaction meaning when `valid_out=0`; the microarchitecture specification defines whether invalid cycles drive zero or retain previous values.

## 9. Boundary Examples

| Case | Rounded code | Output code | Saturation flag |
|---|---:|---:|---:|
| Y0 component = 32767 | N/A | 32767 | 0 |
| Y0 component = 32768 | N/A | 32767 | 1 |
| Y0 component = -32768 | N/A | -32768 | 0 |
| Y0 component = -32769 | N/A | -32768 | 1 |
| Y1 rounded result = 32767 | 32767 | 32767 | 0 |
| Y1 rounded result = 32768 | 32768 | 32767 | 1 |
| Y1 rounded result = -32768 | -32768 | -32768 | 0 |
| Y1 rounded result = -32769 | -32769 | -32768 | 1 |
| Positive tie between codes 2 and 3 | 2 | 2 | 0 |
| Positive tie between codes 3 and 4 | 4 | 4 | 0 |
| Negative tie between codes -2 and -3 | -2 | -2 | 0 |
| Negative tie between codes -3 and -4 | -4 | -4 | 0 |

Codes in this table are target Q1.15 integer encodings, not real-number values.

## 10. Bit-Exact Consistency

For every valid transaction, the Python model, V0 RTL, V1 RTL, and testbenches must agree bit for bit on all four outputs and all four component flags. Any `y0_sat` or `y1_sat` field must equal the OR reduction of its two component flags.

V0 is combinational and V1 has fixed pipeline latency; only observation time may differ. Language-default rounding, host floating point, or implicit width rules must not replace this contract. Random expected values come from the integer model; floating point is only auxiliary error analysis.

Any conflict among simulation, Python, synthesis behavior, and this specification must be analyzed as an implementation error or specification defect before RTL behavior is changed.

## 11. Required Fixed-Point Scenarios

At minimum, verify:

1. all-zero inputs;
2. Q1.15 minimum `0x8000` and maximum `0x7FFF`;
3. positive and negative extrema of `A+B` and `A-B`;
4. `W=0`, near-`+1`, exact `-1`, and common unit-circle coefficients;
5. Y0 exactly at each boundary;
6. Y0 one code beyond each boundary;
7. Y1 discarded fractions below, equal to, and above half a target LSB;
8. positive/negative ties with even/odd retained LSBs;
9. rounding increments that create positive or negative overflow;
10. a wide value slightly beyond the numerical boundary that still rounds in range;
11. real-only and imaginary-only saturation patterns;
12. simultaneous saturation of two components;
13. inputs approaching the maximum complex-combination magnitude; and
14. large fixed-seed random regression against the integer model.

The common CSV has 17 columns: one label, six inputs, four outputs, two derived aggregate flags, and four component flags. V0 and V1 consume the same numerical fields; V1 additionally verifies latency, bubbles, and reset. The current 1071-vector regression passes both versions but is not exhaustive over the 96-bit input space.

## 12. Frozen Decisions

- Every component of `A`, `B`, and `W` is 16-bit Q1.15.
- Every component of `Y_0` and `Y_1` is 16-bit Q1.15.
- Add/subtract intermediates are 17-bit Q2.15.
- Individual real products are 33-bit Q3.30.
- Complex combinations execute after explicit 34-bit extension and remain 34-bit Q4.30 until quantization.
- Y1 uses RNE to reduce 30 fractional bits to 15.
- Y0 requires no fractional rounding.
- Every output saturates rather than wraps.
- The order is round, range-check, then saturate.
- Four component flags are emitted.
- `W` accepts any legal Q1.15 encoding; unit magnitude is not checked.

## 13. Delegated Decisions

Pipeline depth and register locations, V0/V1 latency, valid/reset behavior, invalid-cycle output policy, helper-module organization, target-specific multiplier mapping, and multi-stage FFT scaling/SNR policy belong to the microarchitecture or verification documents.

Frequent saturation in a multi-stage FFT indicates that dynamic range or inter-stage scaling requires redesign. Saturation defines overflow behavior; it is not a complete FFT scaling strategy.
