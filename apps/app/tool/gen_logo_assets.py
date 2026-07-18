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
"""
from __future__ import annotations

import pathlib
import re

APP = pathlib.Path(__file__).resolve().parents[1]
LOGO = APP / "assets" / "images" / "logo.svg"
FAVICON = APP / "web" / "favicon.svg"

MAROON = "#960000"
DISC = 512  # favicon viewBox is DISC x DISC
INSET = 0.86  # glyph width as a fraction of the disc (matches SaltLogoMark)


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

    scale = (DISC * INSET) / w
    tx = (DISC - w * scale) / 2
    ty = (DISC - h * scale) / 2
    FAVICON.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {DISC} {DISC}" '
        f'width="{DISC}" height="{DISC}">\n'
        f'  <circle cx="{DISC // 2}" cy="{DISC // 2}" r="{DISC // 2}" fill="{MAROON}"/>\n'
        f'  <g fill="#ffffff" transform="translate({tx:.2f},{ty:.2f}) '
        f'scale({scale:.5f})">{inner}</g>\n'
        "</svg>\n"
    )
    n = FAVICON.read_text().count("<path")
    print(f"web/favicon.svg: regenerated ({n} paths, glyph {INSET:.0%} of disc)")


if __name__ == "__main__":
    main()
