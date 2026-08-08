#!/usr/bin/env python3
"""Turn a Phosphor SVG into an SF Symbols template and write it as a .symbolset.

Wandr is otherwise entirely SF Symbols, so a handful of Phosphor glyphs only earn their
place if they arrive as symbols too — tinting with `foregroundStyle`, scaling with the
text beside them, and sitting on the same baseline. That means an SF Symbols *template*:
an SVG with named weight/size layers and cap-height guides, which is what `actool`
validates against.

The three required sources (Ultralight-S, Regular-S, Black-S) must share anchor count,
start point and winding direction or the interpolation between them tears. Phosphor's own
weights do not — thin and bold are separately drawn, with different point counts — so the
same path goes into every slot. The consequence is stated plainly: these glyphs do not get
heavier at heavier font weights. They render correctly at every size and inherit colour;
they just will not weight-match a `.bold` SF Symbol beside them. For the static row icons
this is used for, that trade is invisible.

Phosphor's *duotone* weight does not survive the trip, and this is worth recording because
it is invisible until you look at a large size. Duotone expresses its second tone as
`opacity="0.2"` on a background path, and the symbol renderer discards per-path opacity —
every path comes out at full strength, so shield-check rendered as a solid navy shield with
its check swallowed. Two tones in a real symbol come from *annotated layers*, which only
the SF Symbols app writes. So these use `bold`: one path, no holes that depend on a fill
rule, and a stroke weight that sits correctly beside SF Symbols at label sizes.
"""

import json
import pathlib
import re
import subprocess
import sys

PHOSPHOR = "https://raw.githubusercontent.com/phosphor-icons/core/main/assets/{weight}/{name}-{weight}.svg"

# The canvas actool expects, and the guides inside it. Values are the Apple template's own.
CANVAS_W, CANVAS_H = 3300, 2200

# Per-scale geometry: (x of left margin, capline y, baseline y).
# Small, Medium and Large sit in three columns; the glyph is drawn between capline and
# baseline in each, scaled about the cap height so it optically matches SF Pro beside it.
SCALES = {
    "S": {"x": 263.0, "cap": 696.0, "base": 892.0},
    "M": {"x": 1290.0, "cap": 696.0, "base": 892.0},
    "L": {"x": 2317.0, "cap": 696.0, "base": 892.0},
}
WEIGHTS = [
    "Ultralight", "Thin", "Light", "Regular",
    "Medium", "Semibold", "Bold", "Heavy", "Black",
]

# How tall the glyph is drawn relative to cap height, and how far its centre sits above the
# baseline. Tuned by eye against `hand.raised.fill` at the same font size — SF Symbols are
# drawn a little taller than cap height and hang slightly below the baseline.
GLYPH_SCALE = 1.42
GLYPH_DROP = 0.10


def fetch(name: str, weight: str) -> str:
    url = PHOSPHOR.format(name=name, weight=weight)
    out = subprocess.run(["curl", "-sSL", "--max-time", "30", url],
                         capture_output=True, text=True, check=True).stdout
    if "<svg" not in out:
        raise SystemExit(f"not an svg: {url}\n{out[:200]}")
    return out


def paths_of(svg: str) -> list[tuple[str, str | None]]:
    """Every `d` in the source. Opacity is carried through for completeness, but see the note
    above: the symbol renderer drops it, so a source that depends on it will look wrong."""
    found = []
    for tag in re.findall(r"<path\b[^>]*/?>", svg):
        d = re.search(r'\bd="([^"]+)"', tag)
        if not d:
            continue
        opacity = re.search(r'\bopacity="([^"]+)"', tag)
        found.append((d.group(1), opacity.group(1) if opacity else None))
    if not found:
        raise SystemExit("no <path d=…> in source")
    return found


def transform(scale_key: str) -> str:
    """Phosphor draws on a 256-unit box with y down, which is also the SVG convention here,
    so this is a scale and a translate — no flip. The glyph is centred on the cap band."""
    g = SCALES[scale_key]
    cap_height = g["base"] - g["cap"]
    size = cap_height * GLYPH_SCALE
    factor = size / 256.0
    x = g["x"]
    y = g["cap"] - (size - cap_height) / 2 + cap_height * GLYPH_DROP
    return f"translate({x:.3f}, {y:.3f}) scale({factor:.6f})"


def template(paths: list[tuple[str, str | None]]) -> str:
    guides = []
    for key, g in SCALES.items():
        for label, y in (("Capline", g["cap"]), ("Baseline", g["base"])):
            guides.append(
                f'<line id="{label}-{key}" x1="{g["x"]:.3f}" y1="{y:.3f}" '
                f'x2="{g["x"] + 700:.3f}" y2="{y:.3f}" stroke="#27AAE1" stroke-width="0.5"/>'
            )

    symbols = []
    for weight in WEIGHTS:
        for key in SCALES:
            body = "".join(
                f'<path d="{d}"{f" opacity=\"{o}\"" if o else ""}/>' for d, o in paths
            )
            symbols.append(
                f'<g id="{weight}-{key}" transform="{transform(key)}">{body}</g>'
            )

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS_W}" height="{CANVAS_H}" '
        f'viewBox="0 0 {CANVAS_W} {CANVAS_H}">'
        f'<g id="Notes"></g>'
        f'<g id="Guides">{"".join(guides)}</g>'
        f'<g id="Symbols">{"".join(symbols)}</g>'
        f"</svg>"
    )


def write(asset_root: pathlib.Path, symbol_name: str, source: str, weight: str) -> None:
    svg = fetch(source, weight)
    folder = asset_root / f"{symbol_name}.symbolset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{source}.svg").write_text(template(paths_of(svg)))
    (folder / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "symbols": [{"filename": f"{source}.svg", "idiom": "universal"}],
    }, indent=2) + "\n")
    print(f"wrote {folder.name}")


ICONS = [
    # (symbol name in the asset catalogue, phosphor icon, phosphor weight)
    ("wandr.shield.check", "shield-check", "bold"),
    ("wandr.chats", "chats-circle", "bold"),
    ("wandr.clipboard.text", "clipboard-text", "bold"),
]

if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "Wandr/Assets.xcassets/Symbols")
    for symbol, source, weight in ICONS:
        write(root, symbol, source, weight)
