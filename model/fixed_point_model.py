"""Bit-exact integer reference model for the Radix-2 DIF butterfly.

All public inputs and outputs are signed integer encodings of Q1.15 values.
The model deliberately uses integer arithmetic only; it does not model clocks or
RTL propagation delay.
"""

from __future__ import annotations

from dataclasses import dataclass


Q15_MIN = -(1 << 15)
Q15_MAX = (1 << 15) - 1
Q15_SCALE = 1 << 15


@dataclass(frozen=True)
class ComplexQ15:
    re: int
    im: int

    def __post_init__(self) -> None:
        _require_q15("re", self.re)
        _require_q15("im", self.im)


@dataclass(frozen=True)
class ButterflyResult:
    y0: ComplexQ15
    y1: ComplexQ15
    sat_y0_re: bool
    sat_y0_im: bool
    sat_y1_re: bool
    sat_y1_im: bool

    @property
    def y0_sat(self) -> bool:
        """Backward-compatible aggregate flag used by the V0 interface."""
        return self.sat_y0_re or self.sat_y0_im

    @property
    def y1_sat(self) -> bool:
        """Backward-compatible aggregate flag used by the V0 interface."""
        return self.sat_y1_re or self.sat_y1_im


def _require_q15(name: str, value: int) -> None:
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError(f"{name} must be an integer Q1.15 encoding")
    if not Q15_MIN <= value <= Q15_MAX:
        raise ValueError(f"{name}={value} is outside signed 16-bit Q1.15")


def saturate_q15(value: int) -> tuple[int, bool]:
    """Clamp an integer with 15 fractional bits to signed Q1.15."""
    if value > Q15_MAX:
        return Q15_MAX, True
    if value < Q15_MIN:
        return Q15_MIN, True
    return value, False


def round_ties_to_even_abs(value: int, discarded_bits: int) -> int:
    """Divide by 2**discarded_bits using round-to-nearest, ties-to-even.

    Rounding the magnitude and restoring the sign makes negative half-way cases
    explicit and independent of a language's signed-shift convention.
    """
    if discarded_bits <= 0:
        raise ValueError("discarded_bits must be positive")

    magnitude = abs(value)
    quotient, remainder = divmod(magnitude, 1 << discarded_bits)
    half = 1 << (discarded_bits - 1)
    increment = remainder > half or (remainder == half and quotient & 1)
    rounded_magnitude = quotient + int(increment)
    return -rounded_magnitude if value < 0 else rounded_magnitude


def quantize_q30_to_q15(value: int) -> tuple[int, bool]:
    """RNE-quantize a Q*.30 integer and then saturate to Q1.15."""
    rounded = round_ties_to_even_abs(value, discarded_bits=15)
    return saturate_q15(rounded)


def butterfly(a: ComplexQ15, b: ComplexQ15, w: ComplexQ15) -> ButterflyResult:
    """Evaluate Y0=A+B and Y1=(A-B)W with the frozen MVP rules."""
    sum_re = a.re + b.re
    sum_im = a.im + b.im
    diff_re = a.re - b.re
    diff_im = a.im - b.im

    y0_re, y0_re_sat = saturate_q15(sum_re)
    y0_im, y0_im_sat = saturate_q15(sum_im)

    product_re = diff_re * w.re - diff_im * w.im
    product_im = diff_re * w.im + diff_im * w.re

    # This is the mathematical counterpart of the RTL's 34-to-33-bit assertion.
    if not -(1 << 32) <= product_re <= (1 << 32) - 1:
        raise AssertionError(f"real product does not fit signed 33 bits: {product_re}")
    if not -(1 << 32) <= product_im <= (1 << 32) - 1:
        raise AssertionError(f"imag product does not fit signed 33 bits: {product_im}")

    y1_re, y1_re_sat = quantize_q30_to_q15(product_re)
    y1_im, y1_im_sat = quantize_q30_to_q15(product_im)

    return ButterflyResult(
        y0=ComplexQ15(y0_re, y0_im),
        y1=ComplexQ15(y1_re, y1_im),
        sat_y0_re=y0_re_sat,
        sat_y0_im=y0_im_sat,
        sat_y1_re=y1_re_sat,
        sat_y1_im=y1_im_sat,
    )


def q15_from_float(value: float) -> int:
    """Quantize a coefficient to Q1.15 for vector generation only.

    Python's round implements ties-to-even. Saturation is required because +1.0
    is not representable in Q1.15.
    """
    scaled = round(value * Q15_SCALE)
    return min(Q15_MAX, max(Q15_MIN, scaled))
