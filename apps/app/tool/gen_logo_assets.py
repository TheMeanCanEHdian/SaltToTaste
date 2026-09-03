#!/usr/bin/env python3
"""Regenerate the derived brand-logo assets from ``assets/images/logo.svg``.

Run this after replacing/editing ``logo.svg`` (e.g. re-exporting the vector):

    cd apps/app && python3 tool/gen_logo_assets.py

It does two things, both idempotent:

1. Ensures ``fill="currentColor"`` on ``logo.svg``'s wrapper ``<g>``. The in-app
   widgets (SaltLogoGlyph/Mark/Banner) tint the mark through
   ``SvgTheme(currentColor:)`` — a ``srcIn`` ``colorFilter`` renders the SVG
   BLANK on CanvasKit (web), verified directly, so ``currentColor`` is the only
   reliable tint. A fresh export drops this attribute, which would silently blank
   the mark in the app (invisible to Skia goldens), so we re-add it here.

2. Regenerates ``web/favicon.svg`` (maroon disc + white glyph) so the tab icon
   picks up any new elements. The favicon paints an explicit white and must NOT
   carry ``currentColor`` (it would resolve to black on the disc), so the glyph
   content is stripped of it before being wrapped.

3. Regenerates the PWA icons under ``web/icons/`` (declared by
   ``web/manifest.json`` and as the apple-touch-icon). Both kinds are an
   OPAQUE full-bleed maroon square — ``qlmanage`` flattens onto white, so a
   transparent disc is not on offer, and Apple asks for opaque touch icons
   anyway. The plain 192/512 ones carry the glyph at the favicon's inset; the
   maskable ones hold it inside the 80% safe zone that Android's icon masks
   keep. Rasterised with macOS's built-in ``qlmanage`` (no SVG rasteriser is a
   project dependency); on any other OS this step is skipped with a note — the
   PNGs are committed, so only the machine that edits the logo needs it.
   ``qlmanage`` exits 0 and writes SOMETHING for any input, so each PNG is
   checked for its expected size and for not being a blank tile.
"""
from __future__ import annotations

import pathlib
import re
import shutil
import struct
import subprocess
import tempfile
import zlib

APP = pathlib.Path(__file__).resolve().parents[1]
LOGO = APP / "assets" / "images" / "logo.svg"
FAVICON = APP / "web" / "favicon.svg"
ICONS = APP / "web" / "icons"

MAROON = "#960000"
DISC = 512  # favicon viewBox is DISC x DISC
INSET = 0.86  # glyph width as a fraction of the disc (matches SaltLogoMark)
SAFE_ZONE = 0.8  # maskable icons: the inner circle Android masks never cut


def main() -> None:
    svg = LOGO.read_text()

    # 1. Idempotently ensure the currentColor tint hook on the wrapper group.
    if 'fill="currentColor"' not in svg:
        patched = svg.replace('<g><g id="Pan">', '<g fill="currentColor"><g id="Pan">', 1)
        if patched == svg:
            raise SystemExit(
                "could not find the '<g><g id=\"Pan\">' wrapper to patch — "
                "did the SVG structure change? Patch fill=\"currentColor\" by hand."
            )
        svg = patched
        LOGO.write_text(svg)
        print(f"logo.svg: added fill=\"currentColor\" on the wrapper group")
    else:
        print("logo.svg: currentColor tint already present")

    # 2. Regenerate the favicon from the drawing content (viewBox read live so a
    #    resized export still centres correctly).
    vb = re.search(r'viewBox="([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)"', svg)
    if not vb:
        raise SystemExit("logo.svg has no viewBox")
    _, _, w, h = (float(x) for x in vb.groups())
    inner = re.search(r"<svg\b[^>]*>(.*)</svg>", svg, re.S).group(1).strip()
    inner = inner.replace(' fill="currentColor"', "")  # favicon fills white itself

    def icon_svg(inset: float, full_bleed: bool) -> str:
        scale = (DISC * inset) / w
        tx = (DISC - w * scale) / 2
        ty = (DISC - h * scale) / 2
        shape = (
            f'<rect width="{DISC}" height="{DISC}" fill="{MAROON}"/>'
            if full_bleed
            else f'<circle cx="{DISC // 2}" cy="{DISC // 2}" r="{DISC // 2}" fill="{MAROON}"/>'
        )
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {DISC} {DISC}" '
            f'width="{DISC}" height="{DISC}">\n'
            f"  {shape}\n"
            f'  <g fill="#ffffff" transform="translate({tx:.2f},{ty:.2f}) '
            f'scale({scale:.5f})">{inner}</g>\n'
            "</svg>\n"
        )

    FAVICON.write_text(icon_svg(INSET, full_bleed=False))
    n = FAVICON.read_text().count("<path")
    print(f"web/favicon.svg: regenerated ({n} paths, glyph {INSET:.0%} of disc)")

    # 3. PWA icons: opaque full-bleed squares (qlmanage flattens onto white,
    #    so the disc's transparent corners would ship as white ones). Plain =
    #    glyph at the favicon inset; maskable = glyph inside the safe zone.
    if not shutil.which("qlmanage"):
        print("web/icons: skipped (needs macOS qlmanage to rasterise; PNGs are committed)")
        return
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = pathlib.Path(tmp)
        for name, svg_text in (
            ("Icon", icon_svg(INSET, full_bleed=True)),
            ("Icon-maskable", icon_svg(INSET * SAFE_ZONE, full_bleed=True)),
        ):
            src = tmp_dir / f"{name}.svg"
            src.write_text(svg_text)
            for size in (192, 512):
                run = subprocess.run(
                    ["qlmanage", "-t", "-s", str(size), "-o", tmp, str(src)],
                    capture_output=True,
                    text=True,
                )
                out = tmp_dir / f"{name}.svg.png"
                if run.returncode != 0 or not out.exists():
                    raise SystemExit(
                        f"qlmanage failed for {name} at {size}px (exit {run.returncode}):\n"
                        f"{run.stdout}{run.stderr}"
                    )
                _check_png(out, size)
                out.replace(ICONS / f"{name}-{size}.png")
                print(f"web/icons/{name}-{size}.png: regenerated")


def _check_png(path: pathlib.Path, size: int) -> None:
    """Refuse a PNG that is not ``size``×``size`` or that is a blank tile.

    ``qlmanage`` exits 0 and writes an image for any input at all — plain text,
    a broken path — so a fresh export that WebKit cannot draw would otherwise
    ship as a white square with "regenerated" printed next to it.
    """
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path.name}: not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (size, size):
        raise SystemExit(f"{path.name}: expected {size}x{size}, got {width}x{height}")
    idat, pos = b"", 8
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        if kind == b"IDAT":
            idat += data[pos + 8 : pos + 8 + length]
        pos += 12 + length
    # A uniform tile compresses to filter bytes plus a handful of values; the
    # real glyph over maroon uses far more than a dozen distinct byte values.
    if len(set(zlib.decompress(idat))) < 16:
        raise SystemExit(f"{path.name}: rendered blank — does logo.svg still draw?")


if __name__ == "__main__":
    main()
