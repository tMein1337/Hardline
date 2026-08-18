# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Draws Hardline's application icon and writes every platform's asset.

Run from the repository root:

    python tool/generate_icons.py

The mark is drawn here rather than kept as a binary blob so that it is part of
the Corresponding Source in a form that can actually be modified: the icon is
described by the numbers below, and changing one of them and re-running is the
whole edit cycle. It also means the repository ships no image whose provenance
cannot be checked.

Deliberately stdlib-only -- zlib and struct are enough to write a PNG, and an
ICO is a small header around a set of PNGs. Adding Pillow for this would put a
build-time dependency in the way of regenerating an icon.

## The mark

A step in a line: a heavy horizontal trace that rises once and carries on. It
reads as a hard line with a break in it, and as the horizon on an attitude
indicator, which is where the rest of the interface takes its cues from. Under
it sits the same split rule the app draws beside a message that names you.

It is drawn from orthogonal rectangles only, so it stays crisp at 16px where a
curve or a diagonal would turn to mush.
"""

import math
import os
import struct
import zlib

# ── Palette, matching lib/theme/palettes.dart ────────────────────────────
BLACK = (0x0A, 0x0A, 0x0B)
ORANGE = (0xFF, 0x7A, 0x18)

# ── Geometry, in a 0..1 square ───────────────────────────────────────────
CORNER_RADIUS = 0.215

TRACE = 0.115          # thickness of the heavy line
LEFT_X = 0.145         # where the trace enters
RIGHT_X = 0.855        # where it leaves
STEP_X = 0.455         # where it rises
LOW_Y = 0.605          # entry height
HIGH_Y = 0.395         # height after the step

RULE_THICK = 0.040     # the split rule beneath
RULE_Y = 0.790
RULE_LEFT = 0.145
RULE_GAP_A = 0.375     # first segment ends
RULE_GAP_B = 0.455     # second segment starts
RULE_RIGHT = 0.640

SUPERSAMPLE = 4        # per axis, so 16x samples per pixel


def rounded_rect_covers(x, y, radius):
    """Whether (x, y) in the unit square is inside the rounded background."""
    cx = min(max(x, radius), 1.0 - radius)
    cy = min(max(y, radius), 1.0 - radius)
    dx, dy = x - cx, y - cy
    if dx == 0.0 or dy == 0.0:
        return 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0
    return math.hypot(dx, dy) <= radius


def trace_rects():
    """The heavy step line, as a union of axis-aligned rectangles."""
    half = TRACE / 2.0
    return [
        # Lower arm, run out to the far side of the riser so the join is solid.
        (LEFT_X, LOW_Y - half, STEP_X + half, LOW_Y + half),
        # The riser.
        (STEP_X - half, HIGH_Y - half, STEP_X + half, LOW_Y + half),
        # Upper arm.
        (STEP_X - half, HIGH_Y - half, RIGHT_X, HIGH_Y + half),
    ]


def rule_rects():
    """The split rule under the trace: two segments with a gap."""
    half = RULE_THICK / 2.0
    return [
        (RULE_LEFT, RULE_Y - half, RULE_GAP_A, RULE_Y + half),
        (RULE_GAP_B, RULE_Y - half, RULE_RIGHT, RULE_Y + half),
    ]


def in_any(x, y, rects):
    for x0, y0, x1, y1 in rects:
        if x0 <= x <= x1 and y0 <= y <= y1:
            return True
    return False


def render(size, maskable=False):
    """Returns RGBA bytes for a `size` x `size` icon.

    `maskable` shrinks the mark into the middle 80% and fills the whole square,
    which is what a maskable web icon needs: the platform may crop it to any
    shape, and anything in the outer band can be cut away.
    """
    trace = trace_rects()
    rule = rule_rects()
    inset = 0.10 if maskable else 0.0

    rows = []
    step = 1.0 / (size * SUPERSAMPLE)
    for py in range(size):
        row = bytearray()
        for px in range(size):
            bg_hits = 0
            fg_hits = 0
            for sy in range(SUPERSAMPLE):
                y = (py * SUPERSAMPLE + sy + 0.5) * step
                for sx in range(SUPERSAMPLE):
                    x = (px * SUPERSAMPLE + sx + 0.5) * step

                    if maskable:
                        bg_hits += 1  # full bleed
                    elif rounded_rect_covers(x, y, CORNER_RADIUS):
                        bg_hits += 1

                    # Map the drawing into the safe area when maskable.
                    mx = (x - inset) / (1.0 - 2 * inset) if maskable else x
                    my = (y - inset) / (1.0 - 2 * inset) if maskable else y
                    if in_any(mx, my, trace) or in_any(mx, my, rule):
                        fg_hits += 1

            total = SUPERSAMPLE * SUPERSAMPLE
            bg_a = bg_hits / total
            fg_a = fg_hits / total
            # The mark never spills outside the background plate.
            fg_a = min(fg_a, bg_a)

            r = BLACK[0] * (bg_a - fg_a) + ORANGE[0] * fg_a
            g = BLACK[1] * (bg_a - fg_a) + ORANGE[1] * fg_a
            b = BLACK[2] * (bg_a - fg_a) + ORANGE[2] * fg_a
            alpha = bg_a

            if alpha > 0:
                # Un-premultiply: PNG stores straight alpha.
                r, g, b = r / alpha, g / alpha, b / alpha
            row += bytes(
                (
                    int(round(min(255, max(0, r)))),
                    int(round(min(255, max(0, g)))),
                    int(round(min(255, max(0, b)))),
                    int(round(alpha * 255)),
                )
            )
        rows.append(bytes(row))
    return rows


def png_bytes(rows, size):
    """A minimal 8-bit RGBA PNG."""
    raw = b"".join(b"\x00" + row for row in rows)  # filter type 0 per scanline

    def chunk(tag, data):
        body = tag + data
        return (
            struct.pack(">I", len(data))
            + body
            + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def ico_bytes(pngs):
    """An ICO wrapping PNG images. `pngs` is [(size, png_bytes), ...]."""
    count = len(pngs)
    header = struct.pack("<HHH", 0, 1, count)
    offset = 6 + 16 * count
    entries, blobs = b"", b""
    for size, blob in pngs:
        # 0 in the width/height byte means 256.
        dim = 0 if size >= 256 else size
        entries += struct.pack(
            "<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), offset
        )
        offset += len(blob)
        blobs += blob
    return header + entries + blobs


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)
    print(f"  {path}  ({len(data):,} bytes)")


def png(size, maskable=False):
    return png_bytes(render(size, maskable=maskable), size)


def main():
    if not os.path.isdir("windows") or not os.path.isfile("pubspec.yaml"):
        raise SystemExit("Run this from the repository root.")

    # Rendered once per size and reused across platforms.
    cache = {}

    def at(size):
        if size not in cache:
            cache[size] = png(size)
        return cache[size]

    print("Windows:")
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    write(
        os.path.join("windows", "runner", "resources", "app_icon.ico"),
        ico_bytes([(s, at(s)) for s in ico_sizes]),
    )

    print("Web:")
    write(os.path.join("web", "favicon.png"), at(32))
    for size in (192, 512):
        write(os.path.join("web", "icons", f"Icon-{size}.png"), at(size))
        write(
            os.path.join("web", "icons", f"Icon-maskable-{size}.png"),
            png(size, maskable=True),
        )

    print("macOS:")
    for size in (16, 32, 64, 128, 256, 512, 1024):
        write(
            os.path.join(
                "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset",
                f"app_icon_{size}.png",
            ),
            at(size),
        )

    print("iOS:")
    ios = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, size in sorted(ios.items()):
        write(
            os.path.join(
                "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset", name
            ),
            at(size),
        )

    print("Android:")
    android = {
        "mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192,
    }
    for folder, size in sorted(android.items()):
        write(
            os.path.join(
                "android", "app", "src", "main", "res", folder,
                "ic_launcher.png",
            ),
            at(size),
        )

    print("\nDone.")


if __name__ == "__main__":
    main()
