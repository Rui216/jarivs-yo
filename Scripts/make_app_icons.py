#!/usr/bin/env python3
"""Generates the JARVIS app icon set.

The icon is drawn procedurally so it can be regenerated or restyled without
any image editing tools, and so the repository carries no binary artwork that
cannot be reproduced. Shapes are rasterised with signed distance functions and
analytic anti aliasing, then box filtered down to every size the macOS app
icon set requires.

Usage:
    python3 Scripts/make_app_icons.py

Writes into Jarvis/Resources/Assets.xcassets/AppIcon.appiconset/ and rewrites
the Contents.json next to it.
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "Jarvis" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
MASTER_SIZE = 1024

# Palette, matching JarvisTheme.
CANVAS_TOP = (0x14, 0x23, 0x3F)
CANVAS_BOTTOM = (0x06, 0x0A, 0x16)
ACCENT = (0x38, 0xD8, 0xEE)
ACCENT_BRIGHT = (0x7B, 0xF0, 0xFF)

# Sizes required by the macOS app icon set: (pixel size, filename).
SIZES: list[tuple[int, str]] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

CONTENTS_ENTRIES = [
    ("16x16", "1x", "icon_16x16.png"),
    ("16x16", "2x", "icon_16x16@2x.png"),
    ("32x32", "1x", "icon_32x32.png"),
    ("32x32", "2x", "icon_32x32@2x.png"),
    ("128x128", "1x", "icon_128x128.png"),
    ("128x128", "2x", "icon_128x128@2x.png"),
    ("256x256", "1x", "icon_256x256.png"),
    ("256x256", "2x", "icon_256x256@2x.png"),
    ("512x512", "1x", "icon_512x512.png"),
    ("512x512", "2x", "icon_512x512@2x.png"),
]


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return low if value < low else high if value > high else value


def mix(a: tuple[float, float, float], b: tuple[float, float, float], t: float):
    t = clamp(t)
    return (
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    )


def rounded_rect_sdf(px: float, py: float, half: float, radius: float) -> float:
    """Distance from a point to a rounded square centred on the origin."""
    qx = abs(px) - (half - radius)
    qy = abs(py) - (half - radius)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - radius


def hexagon_sdf(px: float, py: float, radius: float) -> float:
    """Distance from a point to a regular hexagon centred on the origin."""
    angle = math.pi / 6.0
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)

    fold = (math.atan2(px, py) + angle) % (2 * angle) - angle
    length = math.hypot(px, py)
    qx = length * math.cos(fold)
    qy = length * abs(math.sin(fold))

    qx -= radius * cos_a
    qy -= radius * sin_a
    shift = clamp(-(qx * cos_a + qy * sin_a), 0.0, radius)
    qx += cos_a * shift
    qy += sin_a * shift

    distance = math.hypot(qx, qy)
    return distance if qx >= 0 or qy < 0 else -distance


def shade(x: float, y: float, size: int) -> tuple[int, int, int, int]:
    """Returns the RGBA of one pixel of the master icon."""
    centre = size / 2.0
    px = x + 0.5 - centre
    py = y + 0.5 - centre

    margin = size * 0.085
    body_half = (size - 2 * margin) / 2.0
    body_radius = body_half * 0.42

    body_distance = rounded_rect_sdf(px, py, body_half, body_radius)
    body_coverage = clamp(0.5 - body_distance)
    if body_coverage <= 0.0:
        return (0, 0, 0, 0)

    # Vertical gradient over the icon body.
    t = clamp((y - margin) / (size - 2 * margin))
    red, green, blue = mix(CANVAS_TOP, CANVAS_BOTTOM, t)

    # Soft accent halo behind the mark.
    halo = math.exp(-max(0.0, math.hypot(px, py) - size * 0.16) / (size * 0.10))
    red, green, blue = mix((red, green, blue), ACCENT, halo * 0.16)

    # Hexagon ring.
    ring_radius = size * 0.235
    ring_thickness = size * 0.052
    ring_distance = abs(hexagon_sdf(px, py, ring_radius)) - ring_thickness / 2.0
    ring_coverage = clamp(0.5 - ring_distance)
    if ring_coverage > 0.0:
        gradient = clamp(0.5 - py / (size * 0.9))
        ring_colour = mix(ACCENT_BRIGHT, ACCENT, gradient)
        red, green, blue = mix((red, green, blue), ring_colour, ring_coverage)

    # Inner hexagon, translucent, and a bright core.
    inner_distance = hexagon_sdf(px, py, ring_radius * 0.55)
    inner_coverage = clamp(0.5 - inner_distance)
    if inner_coverage > 0.0:
        red, green, blue = mix((red, green, blue), ACCENT, inner_coverage * 0.22)

    core_distance = math.hypot(px, py) - size * 0.038
    core_coverage = clamp(0.5 - core_distance)
    if core_coverage > 0.0:
        red, green, blue = mix((red, green, blue), ACCENT_BRIGHT, core_coverage)

    alpha = body_coverage
    return (
        int(clamp(red / 255.0) * 255 + 0.5),
        int(clamp(green / 255.0) * 255 + 0.5),
        int(clamp(blue / 255.0) * 255 + 0.5),
        int(clamp(alpha) * 255 + 0.5),
    )


def render_master(size: int = MASTER_SIZE) -> bytearray:
    """Renders the master icon as raw RGBA bytes."""
    buffer = bytearray(size * size * 4)
    index = 0
    for y in range(size):
        for x in range(size):
            red, green, blue, alpha = shade(x, y, size)
            buffer[index] = red
            buffer[index + 1] = green
            buffer[index + 2] = blue
            buffer[index + 3] = alpha
            index += 4
    return buffer


def downsample(master: bytearray, master_size: int, target: int) -> bytearray:
    """Box filters the master image down to a smaller square."""
    if target == master_size:
        return master
    factor = master_size // target
    if factor * target != master_size:
        raise ValueError("target size must divide the master size")

    output = bytearray(target * target * 4)
    samples = factor * factor
    for ty in range(target):
        for tx in range(target):
            red = green = blue = alpha = 0
            for dy in range(factor):
                row = (ty * factor + dy) * master_size
                for dx in range(factor):
                    index = (row + tx * factor + dx) * 4
                    red += master[index]
                    green += master[index + 1]
                    blue += master[index + 2]
                    alpha += master[index + 3]
            out = (ty * target + tx) * 4
            output[out] = red // samples
            output[out + 1] = green // samples
            output[out + 2] = blue // samples
            output[out + 3] = alpha // samples
    return output


def write_png(path: Path, pixels: bytearray, size: int) -> None:
    """Writes 8 bit RGBA pixels as a PNG file."""
    raw = bytearray()
    stride = size * 4
    for row in range(size):
        raw.append(0)  # filter type: none
        raw.extend(pixels[row * stride : (row + 1) * stride])

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(data)


def write_contents_json() -> None:
    images = [
        {
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": size,
        }
        for size, scale, filename in CONTENTS_ENTRIES
    ]
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (ICON_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> int:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Rendering the {MASTER_SIZE} pixel master icon")
    master = render_master()

    written: dict[int, bytearray] = {MASTER_SIZE: master}
    for size, filename in SIZES:
        if size not in written:
            written[size] = downsample(master, MASTER_SIZE, size)
        write_png(ICON_DIR / filename, written[size], size)
        print(f"  wrote {filename} ({size}x{size})")

    write_contents_json()
    print(f"Updated {ICON_DIR.relative_to(ROOT)}/Contents.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
