#!/usr/bin/env python3
"""
Generate multiple translucency variants of boundary graphics for Zone Planner.

Corrected assumption: boundary images typically contain two non-zero alpha levels for the
stroke/fill that differ only by alpha (NOT 255 vs 0 background). We auto-detect the two
most frequent non-zero alpha values per image and remap only those. Fully transparent
background (alpha == 0) is preserved.

For each variant, remap alpha channel as follows:
alpha == detected_high_alpha -> variant.opaque_alpha
alpha == detected_low_alpha  -> variant.transparent_alpha
Special-case: if only one non-zero alpha is detected (the other "lower" alpha
is effectively 0/background), do not touch alpha==0 pixels; instead set all
alpha>0 pixels to the lower of the two target alphas (min(opaque, transparent)).
All other alpha values (including 0 and any anti-aliased in-betweens) are preserved.

Inputs:
- graphics/edge/*.png
- graphics/corner/*.png
- graphics/chart-border.png

Outputs (per variant):
- graphics/edge_<tag>/*.png
- graphics/corner_<tag>/*.png
- graphics/chart-border-<tag>.png

Variants generated:
    tag=a40_15  opaque=0.40  transparent=0.15
    tag=a20_075 opaque=0.20  transparent=0.075
    tag=a10_25  opaque=0.10  transparent=0.25
"""
import os
import sys

from dataclasses import dataclass
from typing import Tuple, cast


@dataclass(frozen=True)
class Variant:
    tag: str
    opaque_alpha: float
    transparent_alpha: float

VARIANTS = [
    Variant("a40_15", 0.40, 0.15),
    Variant("a20_075", 0.20, 0.075),
    Variant("a10_25", 0.10, 0.25),
]

try:
    from PIL import Image  # Pillow
except ImportError:
    print("Error: Pillow is required. Install via 'pip install pillow'.", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # mod root
GFX = os.path.join(ROOT, "graphics")

# Inputs moved under graphics/base
EDGES_IN = os.path.join(GFX, "base", "edge")
CORNERS_IN = os.path.join(GFX, "base", "corner")
CENTERS_IN = os.path.join(GFX, "base", "center")
BORDER_IN = os.path.join(GFX, "base", "chart-border.png")

# Outputs under graphics/<tag>/{edge,corner,center} and chart-border.png per tag
def variant_root(tag: str) -> str:
    return os.path.join(GFX, tag)

def edges_out_dir(tag: str) -> str:
    return os.path.join(variant_root(tag), "edge")

def corners_out_dir(tag: str) -> str:
    return os.path.join(variant_root(tag), "corner")

def centers_out_dir(tag: str) -> str:
    return os.path.join(variant_root(tag), "center")

def border_out_path(tag: str) -> str:
    return os.path.join(variant_root(tag), "chart-border.png")


def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)


def _detect_alpha_modes(img: Image.Image) -> tuple[int|None, int|None]:
    """Detect the two most frequent non-zero alpha values in the image.
    Returns (high_mode, low_mode). If fewer than two distinct non-zero alphas
    exist, low_mode may be None. If none exist, returns (None, None).
    """
    w, h = img.size
    hist = [0] * 256
    for y in range(h):
        for x in range(w):
            rgba = cast(Tuple[int, int, int, int], img.getpixel((x, y)))
            a = rgba[3]
            if a > 0:
                hist[a] += 1
    # Get indices sorted by count desc, then alpha desc to prefer higher alpha as "high_mode"
    non_zero = [(a, c) for a, c in enumerate(hist) if a > 0 and c > 0]
    if not non_zero:
        return None, None
    non_zero.sort(key=lambda t: (t[1], t[0]), reverse=True)
    top = [a for a, _ in non_zero[:2]]
    if len(top) == 1:
        return top[0], None
    # Ensure we report the larger alpha as high_mode regardless of counts
    high, low = (top[0], top[1]) if top[0] >= top[1] else (top[1], top[0])
    return high, low


def transform_image(in_path: str, out_path: str, opaque_alpha: int, transparent_alpha: int) -> None:
    img = Image.open(in_path).convert("RGBA")
    high_mode, low_mode = _detect_alpha_modes(img)
    w, h = img.size
    out = Image.new("RGBA", (w, h))
    changed = 0
    # When the lower alpha among the two is effectively 0 (i.e., only one non-zero
    # alpha was found), we should not replace alpha==0 pixels; instead make all
    # alpha>0 pixels use the lower of the two target alphas.
    # This matches: "If the lower alpha of the two is zero, don't replace the
    # alpha=0 color; replace the alpha>0 values with the lower of the two."
    lower_target_alpha = min(opaque_alpha, transparent_alpha)
    for y in range(h):
        for x in range(w):
            r, g, b, a = cast(Tuple[int, int, int, int], img.getpixel((x, y)))
            if (low_mode is None or low_mode == 0) and a > 0:
                # Single non-zero alpha detected; normalize all non-zero pixels
                # to the lower target alpha while preserving fully transparent ones.
                out.putpixel((x, y), (r, g, b, lower_target_alpha))
                changed += 1
            else:
                if high_mode is not None and a == high_mode:
                    out.putpixel((x, y), (r, g, b, opaque_alpha))
                    changed += 1
                elif low_mode is not None and a == low_mode:
                    out.putpixel((x, y), (r, g, b, transparent_alpha))
                    changed += 1
                else:
                    out.putpixel((x, y), (r, g, b, a))
    ensure_dir(os.path.dirname(out_path))
    out.save(out_path)
    # Add a short diagnostic for the detected modes
    modes_str = f"modes high={high_mode} low={low_mode}; lower_target={lower_target_alpha}"
    print(f"Processed {os.path.relpath(in_path, ROOT)} -> {os.path.relpath(out_path, ROOT)} (changed {changed} pixels; {modes_str})")


def process_folder(in_dir: str, out_dir: str, opaque_alpha: int, transparent_alpha: int) -> int:
    if not os.path.isdir(in_dir):
        print(f"Skip: missing {in_dir}")
        return 0
    ensure_dir(out_dir)
    count = 0
    for name in os.listdir(in_dir):
        if not name.lower().endswith(".png"):
            continue
        src = os.path.join(in_dir, name)
        dst = os.path.join(out_dir, name)
        transform_image(src, dst, opaque_alpha, transparent_alpha)
        count += 1
    return count


def main() -> int:
    total = 0
    for v in VARIANTS:
        oa = int(round(255 * v.opaque_alpha))
        ta = int(round(255 * v.transparent_alpha))
        total += process_folder(EDGES_IN, edges_out_dir(v.tag), oa, ta)
        total += process_folder(CORNERS_IN, corners_out_dir(v.tag), oa, ta)
        total += process_folder(CENTERS_IN, centers_out_dir(v.tag), oa, ta)
        if os.path.isfile(BORDER_IN):
            transform_image(BORDER_IN, border_out_path(v.tag), oa, ta)
            total += 1
    print(f"Done. {total} files processed across {len(VARIANTS)} variants.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
