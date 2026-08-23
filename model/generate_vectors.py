"""Generate reproducible CSV vectors for butterfly_comb verification."""

from __future__ import annotations

import argparse
import csv
import math
import random
from pathlib import Path
from typing import Iterable

from fixed_point_model import (
    Q15_MAX,
    Q15_MIN,
    ButterflyResult,
    ComplexQ15,
    butterfly,
    q15_from_float,
)


Vector = tuple[str, ComplexQ15, ComplexQ15, ComplexQ15]


def directed_vectors() -> list[Vector]:
    """Cases with simple answers plus saturation and sign-boundary stress."""
    return [
        ("all_zero", ComplexQ15(0, 0), ComplexQ15(0, 0), ComplexQ15(0, 0)),
        ("pass_a", ComplexQ15(12345, -12345), ComplexQ15(0, 0), ComplexQ15(Q15_MAX, 0)),
        ("equal_inputs", ComplexQ15(8192, -8192), ComplexQ15(8192, -8192), ComplexQ15(0, Q15_MIN)),
        ("y0_pos_sat", ComplexQ15(Q15_MAX, 0), ComplexQ15(1, 0), ComplexQ15(Q15_MAX, 0)),
        ("y0_neg_sat", ComplexQ15(Q15_MIN, 0), ComplexQ15(-1, 0), ComplexQ15(Q15_MAX, 0)),
        ("max_opposed", ComplexQ15(Q15_MAX, Q15_MIN), ComplexQ15(Q15_MIN, Q15_MAX), ComplexQ15(Q15_MIN, Q15_MIN)),
        ("mixed_signs", ComplexQ15(-16384, 8192), ComplexQ15(4096, -24576), ComplexQ15(23170, -23170)),
    ]


def twiddle_vectors(count: int) -> Iterable[Vector]:
    for index in range(count):
        angle = -2.0 * math.pi * index / count
        w = ComplexQ15(q15_from_float(math.cos(angle)), q15_from_float(math.sin(angle)))
        a = ComplexQ15((index * 7919) % 65536 - 32768, (index * 1543) % 65536 - 32768)
        b = ComplexQ15((index * 3571) % 65536 - 32768, (index * 2377) % 65536 - 32768)
        yield f"twiddle_{index}", a, b, w


def random_vectors(count: int, seed: int) -> Iterable[Vector]:
    rng = random.Random(seed)
    for index in range(count):
        values = [rng.randint(Q15_MIN, Q15_MAX) for _ in range(6)]
        yield (
            f"random_{index}",
            ComplexQ15(values[0], values[1]),
            ComplexQ15(values[2], values[3]),
            ComplexQ15(values[4], values[5]),
        )


def row(case: Vector, component_flags: bool = False) -> dict[str, int | str]:
    name, a, b, w = case
    result: ButterflyResult = butterfly(a, b, w)
    output = {
        "case": name,
        "a_re": a.re,
        "a_im": a.im,
        "b_re": b.re,
        "b_im": b.im,
        "w_re": w.re,
        "w_im": w.im,
        "y0_re": result.y0.re,
        "y0_im": result.y0.im,
        "y1_re": result.y1.re,
        "y1_im": result.y1.im,
        "y0_sat": int(result.y0_sat),
        "y1_sat": int(result.y1_sat),
    }
    if component_flags:
        output.update(
            sat_y0_re=int(result.sat_y0_re),
            sat_y0_im=int(result.sat_y0_im),
            sat_y1_re=int(result.sat_y1_re),
            sat_y1_im=int(result.sat_y1_im),
        )
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("tb/test_vectors/butterfly_v0.csv"))
    parser.add_argument("--random-count", type=int, default=1000)
    parser.add_argument("--twiddle-count", type=int, default=64)
    parser.add_argument("--seed", type=int, default=0xB077E2)
    parser.add_argument(
        "--component-flags",
        action="store_true",
        help="append four component-level saturation flags for the V1 interface",
    )
    args = parser.parse_args()

    if args.random_count < 0 or args.twiddle_count <= 0:
        parser.error("random-count must be nonnegative and twiddle-count must be positive")

    cases = [
        *directed_vectors(),
        *twiddle_vectors(args.twiddle_count),
        *random_vectors(args.random_count, args.seed),
    ]
    rows = [row(case, component_flags=args.component_flags) for case in cases]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    print(f"wrote {len(rows)} vectors to {args.output}")


if __name__ == "__main__":
    main()
