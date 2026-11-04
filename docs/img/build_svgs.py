#!/usr/bin/env python3
"""Generates the README illustrations: minimalist, hand-drawn look, warm colours, gentle animations.

Usage:  python3 docs/img/build_svgs.py        (writes the .svg files next to this script)

Design notes:
  * Every SVG carries its own cream card, so it looks the same on GitHub's light and dark themes.
  * CSS only (no scripts, no external resources): GitHub shows the SVG as an image, animations included.
  * The wobbly "hand-drawn" filter is applied only to static strokes; anything that moves stays outside the filtered group
    (otherwise it would be re-rasterised on every frame).
  * `prefers-reduced-motion` switches all animations off.
"""
import os, random

HERE = os.path.dirname(os.path.abspath(__file__))
INK, SOFT, FAINT = "#4A3426", "#7A5A44", "#A98767"
CREAM, EDGE, SAND = "#FBF3E4", "#E6D2AE", "#F2DFC0"
TERRA, TERRA_L = "#C65D3B", "#F3D3C4"
AMBER, AMBER_L = "#E8A33D", "#F7D58E"
ROSE = "#D98A7A"

FONT_H = "ui-rounded,'SF Pro Rounded','Nunito','Segoe UI',system-ui,-apple-system,sans-serif"
FONT_N = "'Segoe Print','Bradley Hand','Chalkboard SE','Ink Free','Marker Felt',ui-rounded,'Segoe UI',system-ui,sans-serif"

BASE_CSS = f"""
  .h{{font:700 28px {FONT_H};fill:{INK}}}
  .t{{font:600 17px {FONT_H};fill:{INK}}}
  .s{{font:500 15px {FONT_H};fill:{SOFT}}}
  .n{{font:500 15px {FONT_N};fill:{SOFT}}}
  .big{{font:800 40px {FONT_H};fill:{INK}}}
  .stroke{{fill:none;stroke:{INK};stroke-width:3;stroke-linecap:round;stroke-linejoin:round}}
  @media (prefers-reduced-motion: reduce){{*{{animation:none!important}}}}
"""

def rough_filter(fid, seed, scale=2.4, freq=0.035):
    return (f'<filter id="{fid}" x="-3%" y="-3%" width="106%" height="106%">'
            f'<feTurbulence type="fractalNoise" baseFrequency="{freq}" numOctaves="2" seed="{seed}" result="n"/>'
            f'<feDisplacementMap in="SourceGraphic" in2="n" scale="{scale}" xChannelSelector="R" yChannelSelector="G"/></filter>')

def wob(x, y, w, h, r=12, j=1.6, seed=0):
    """Rounded rectangle with small imperfections, as if drawn by hand."""
    R = random.Random(seed)
    def p(a, b): return f"{a + R.uniform(-j, j):.1f} {b + R.uniform(-j, j):.1f}"
    return (f"M {p(x + r, y)} L {p(x + w - r, y)} Q {p(x + w, y)} {p(x + w, y + r)} "
            f"L {p(x + w, y + h - r)} Q {p(x + w, y + h)} {p(x + w - r, y + h)} "
            f"L {p(x + r, y + h)} Q {p(x, y + h)} {p(x, y + h - r)} "
            f"L {p(x, y + r)} Q {p(x, y)} {p(x + r, y)} Z")

def check(cx, cy, s=1.0, color=INK, width=4):
    return (f'<path d="M {cx - 9 * s:.1f} {cy + 1 * s:.1f} L {cx - 3 * s:.1f} {cy + 8 * s:.1f} L {cx + 10 * s:.1f} {cy - 8 * s:.1f}" '
            f'fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')

def chevron(cx, cy, direction, color=AMBER, s=9):
    """Small hand-drawn arrow head pointing right/down/left/up."""
    pts = {"r": [(-s, -s), (s * .6, 0), (-s, s)], "l": [(s, -s), (-s * .6, 0), (s, s)],
           "d": [(-s, -s), (0, s * .6), (s, -s)], "u": [(-s, s), (0, -s * .6), (s, s)]}[direction]
    d = "M " + " L ".join(f"{cx + a:.1f} {cy + b:.1f}" for a, b in pts)
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'

def svg(w, h, title, desc, css, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-labelledby="t d">\n'
            f'<title id="t">{title}</title><desc id="d">{desc}</desc>\n'
            f'<defs>{defs}</defs>\n<style>{BASE_CSS}{css}</style>\n'
            f'<rect x="2" y="2" width="{w - 4}" height="{h - 4}" rx="26" fill="{CREAM}"/>\n'
            f'<path d="{wob(3, 3, w - 6, h - 6, r=26, j=1.2, seed=7)}" fill="none" stroke="{EDGE}" stroke-width="2.5"/>\n'
            f'{body}\n</svg>\n')

# ---------------------------------------------------------------- hero
def hero():
    W, H = 800, 240
    css = f"""
  .scr{{animation:flick 13s infinite}}
  @keyframes flick{{0%{{opacity:1}}3%{{opacity:.12}}5%{{opacity:1}}8%{{opacity:.2}}10%{{opacity:.95}}13%{{opacity:.08}}16%{{opacity:1}}20%{{opacity:.3}}23%,100%{{opacity:1}}}}
  .glow{{animation:flick 13s infinite}}
  .ul{{stroke-dasharray:330;stroke-dashoffset:0;animation:draw 13s ease-out infinite}}
  @keyframes draw{{0%{{stroke-dashoffset:330}}16%,92%{{stroke-dashoffset:0}}100%{{stroke-dashoffset:330}}}}
  .d1,.d2,.d3{{animation:bob 6s ease-in-out infinite}}.d2{{animation-delay:-2s}}.d3{{animation-delay:-4s}}
  @keyframes bob{{0%,100%{{transform:translateY(0)}}50%{{transform:translateY(-6px)}}}}
"""
    defs = (rough_filter("r1", 3) +
            f'<radialGradient id="gl" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="{AMBER_L}" stop-opacity=".95"/><stop offset="1" stop-color="{AMBER_L}" stop-opacity="0"/></radialGradient>')
    body = f"""
<circle class="glow" cx="170" cy="118" r="105" fill="url(#gl)"/>
<rect class="scr" x="84" y="58" width="172" height="106" rx="8" fill="{AMBER}"/>
<g filter="url(#r1)">
  <path class="stroke" d="{wob(72, 46, 196, 130, r=14, j=1.8, seed=2)}" stroke-width="4"/>
  <path class="stroke" d="M 44 186 Q 170 200 296 186 L 288 176 L 52 176 Z" stroke-width="4" fill="{SAND}"/>
  <path class="stroke" d="M 150 190 Q 170 194 190 190" stroke-width="3"/>
</g>
<text x="340" y="112" class="h" style="font-size:36px">i915-edp-flicker-fix</text>
<path class="ul" d="M 340 128 q 30 -9 62 -2 t 62 0 t 62 1 t 62 -2 t 62 1" fill="none" stroke="{TERRA}" stroke-width="5" stroke-linecap="round"/>
<text x="340" y="164" class="s" style="font-size:18px">A one-bit fix for a screen that blinks</text>
<text x="340" y="196" class="n" style="font-size:14px">MSI Prestige 16Studio A13VF  ·  Ubuntu 26.04</text>
<circle class="d1" cx="748" cy="44" r="9" fill="{AMBER}"/><circle class="d2" cx="774" cy="78" r="6" fill="{TERRA}" opacity=".85"/><circle class="d3" cx="752" cy="206" r="5" fill="{ROSE}"/>
"""
    return svg(W, H, "Screen flicker fix for i915 eDP panels",
               "A laptop screen that blinks, with a hand-drawn underline below the project name.", css, body, defs)

# ---------------------------------------------------------------- loop
def loop():
    W, H = 800, 340
    loop_path = "M 200 102 L 600 102 Q 612 102 612 114 L 612 240 Q 612 252 600 252 L 200 252 Q 188 252 188 240 L 188 114 Q 188 102 200 102 Z"
    css = f"""
  .dot{{offset-path:path('{loop_path}');offset-rotate:0deg;animation:run 8s linear infinite}}
  @keyframes run{{from{{offset-distance:0%}}to{{offset-distance:100%}}}}
  .belt{{stroke-dasharray:2 11;animation:belt 3s linear infinite}}
  @keyframes belt{{to{{stroke-dashoffset:-26}}}}
  .hot{{animation:hot 8s ease-in-out infinite}}
  @keyframes hot{{0%,55%{{fill:{CREAM}}}70%,88%{{fill:{TERRA_L}}}100%{{fill:{CREAM}}}}}
  .blink{{animation:bl 3.07s steps(1) infinite}}
  @keyframes bl{{0%{{opacity:1}}60%{{opacity:1}}66%{{opacity:.1}}74%{{opacity:1}}82%{{opacity:.15}}90%,100%{{opacity:1}}}}
"""
    defs = rough_filter("r2", 11)
    labels = ["1 · train the link", "2 · backlight on", "3 · +2 s: “a bit is missing?”", "4 · retrain: panel off/on"]
    nodes = [(70, 66, labels[0], False), (480, 66, labels[1], False), (480, 220, labels[2], False), (70, 220, labels[3], True)]
    ns = ""
    for i, (x, y, label, hot) in enumerate(nodes):
        ns += (f'<path class="{"hot" if hot else ""}" d="{wob(x, y, 250, 68, r=16, j=1.6, seed=20 + i)}" fill="{CREAM}" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
               f'<text x="{x + 125}" y="{y + 40}" text-anchor="middle" class="t" style="font-size:16px">{label}</text>')
    arrows = chevron(400, 102, "r") + chevron(612, 177, "d") + chevron(400, 252, "l") + chevron(188, 177, "u")
    body = f"""
<text x="44" y="40" class="n" style="font-size:18px">the loop</text>
<path class="belt" d="{loop_path}" fill="none" stroke="{AMBER}" stroke-width="4" stroke-linecap="round"/>
{arrows}
<circle class="dot" r="9" fill="{TERRA}"/>
<g filter="url(#r2)">{ns}</g>
<g class="blink"><rect x="362" y="136" width="76" height="46" rx="6" fill="{AMBER}"/></g>
<g filter="url(#r2)"><path class="stroke" d="{wob(356, 130, 88, 58, r=8, j=1.2, seed=33)}" stroke-width="3.5"/><path class="stroke" d="M 380 196 H 420" stroke-width="3.5"/></g>
<text x="400" y="216" text-anchor="middle" class="t" style="font-size:20px;font-weight:800">every 3.07 s</text>
<text x="400" y="236" text-anchor="middle" class="n">= the flicker</text>
"""
    return svg(W, H, "The retrain loop",
               "Four steps in a circle: train the eDP link, switch the backlight on, two seconds later the kernel thinks a bit is missing, retrain with a panel power cycle, and repeat every 3.07 seconds.",
               css, body, defs)

# ---------------------------------------------------------------- bit
def bit():
    W, H = 800, 300
    css = f"""
  .lane{{transform-box:fill-box;transform-origin:center;animation:pop .6s cubic-bezier(.3,1.6,.5,1) both}}
  .l1{{animation-delay:.1s}}.l2{{animation-delay:.35s}}.l3{{animation-delay:.6s}}.l4{{animation-delay:.85s}}
  @keyframes pop{{from{{transform:scale(.2);opacity:0}}to{{transform:scale(1);opacity:1}}}}
  .miss{{animation:pulse 2.4s ease-in-out infinite}}
  @keyframes pulse{{0%,100%{{stroke-opacity:1;fill:{TERRA_L}}}50%{{stroke-opacity:.35;fill:{CREAM}}}}}
  .ptr{{animation:nudge 2.4s ease-in-out infinite}}
  @keyframes nudge{{0%,100%{{transform:translateY(0)}}50%{{transform:translateY(5px)}}}}
"""
    lanes = "".join(f'<g class="lane l{i + 1}"><circle cx="{x}" cy="96" r="24" fill="{AMBER}"/>{check(x, 96, 1.0, INK, 4.5)}</g>'
                    for i, x in enumerate((262, 362, 462, 562)))
    bits = ""; x0 = 212
    for k in range(8):
        n = 7 - k; x = x0 + k * 62
        if n == 0:
            bits += (f'<rect class="miss" x="{x}" y="170" width="54" height="54" rx="10" fill="{TERRA_L}" stroke="{TERRA}" stroke-width="3.5" stroke-dasharray="7 6"/>'
                     f'<text x="{x + 27}" y="207" text-anchor="middle" class="t" style="font-size:24px" fill="{TERRA}">0</text>')
        else:
            val = "1" if n == 7 else "0"
            bits += (f'<path d="{wob(x, 170, 54, 54, r=10, j=1.2, seed=40 + k)}" fill="{SAND if val == "1" else CREAM}" stroke="{INK}" stroke-width="2.5"/>'
                     f'<text x="{x + 27}" y="207" text-anchor="middle" class="t" style="font-size:24px">{val}</text>')
        bits += f'<text x="{x + 27}" y="162" text-anchor="middle" class="n" style="font-size:12px">{n}</text>'
    ax = x0 + 7 * 62 + 27
    body = f"""
<text x="44" y="40" class="n" style="font-size:18px">what the panel reports</text>
<text x="756" y="40" text-anchor="end" class="n" style="font-size:15px">everything is locked… except one bit</text>
<text x="86" y="102" class="s" style="font-size:14px" text-anchor="middle">lanes locked</text>
<text x="86" y="121" class="n" style="font-size:12px" text-anchor="middle">0x77 · 0x77</text>
{lanes}
<text x="86" y="206" class="s" style="font-size:14px" text-anchor="middle">DPCD byte 0x204</text>
{bits}
<g class="ptr"><path d="M {ax} 234 L {ax} 254 M {ax - 8} 245 L {ax} 255 L {ax + 8} 245" fill="none" stroke="{TERRA}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/></g>
<text x="{ax}" y="284" text-anchor="end" class="t" style="font-size:15px" fill="{TERRA}">INTERLANE_ALIGN_DONE = 0</text>
<text x="{ax + 16}" y="249" class="n" style="font-size:12.5px" fill="{TERRA}">should be 1</text>
"""
    return svg(W, H, "One missing bit",
               "All four lanes report lock (0x77) but bit 0 of DPCD byte 0x204, INTERLANE_ALIGN_DONE, is zero.", css, body, rough_filter("r3", 5))

# ---------------------------------------------------------------- result
def result():
    W, H = 800, 320
    R = random.Random(4)
    before = [1] * 20 + [0] * 12; R.shuffle(before)
    css = f"""
  .sq{{transform-box:fill-box;transform-origin:center;animation:pop .5s cubic-bezier(.3,1.5,.5,1) both}}
  @keyframes pop{{from{{transform:scale(.2);opacity:0}}to{{transform:scale(1);opacity:1}}}}
  .bad{{animation:pop .5s cubic-bezier(.3,1.5,.5,1) both, tw 3.4s ease-in-out 2.6s infinite}}
  .bad2{{animation:pop .5s cubic-bezier(.3,1.5,.5,1) both, tw 4.7s ease-in-out 3.1s infinite}}
  @keyframes tw{{0%,100%{{opacity:1}}50%{{opacity:.62}}}}
"""
    def sq(i, x, y, bad):
        cls = ("bad" if i % 2 else "bad2") if bad else "sq"
        col = TERRA if bad else AMBER
        return (f'<rect class="{cls}" style="animation-delay:{0.06 * i:.2f}s,{2.6 + (i % 5) * .3:.1f}s" x="{x}" y="{y}" width="24" height="24" rx="6" fill="{col}"/>')
    g1 = "".join(sq(i, 60 + (i % 16) * 30, 98 + (i // 16) * 32, bool(b)) for i, b in enumerate(before))
    g2 = "".join(sq(40 + i, 60 + i * 30, 232, False) for i in range(12))
    body = f"""
<text x="44" y="40" class="n" style="font-size:18px">mode switches that ended in a retrain</text>
<text x="60" y="84" class="s" style="font-weight:700">before (baseline, unpatched)</text>
<rect x="470" y="26" width="16" height="16" rx="4" fill="{TERRA}"/><text x="494" y="39" class="n" style="font-size:13px">ended in a retrain</text>
<rect x="628" y="26" width="16" height="16" rx="4" fill="{AMBER}"/><text x="652" y="39" class="n" style="font-size:13px">no retrain</text>
<g>{g1}</g>
<text x="600" y="120" class="big" style="fill:{TERRA}">20/32</text>
<text x="600" y="146" class="n">retrained</text>
<text x="60" y="218" class="s" style="font-weight:700">with the patch</text>
<g>{g2}</g>
<text x="600" y="256" class="big" style="fill:#C98A1B">0/12</text>
<text x="600" y="282" class="n">retrained</text>
<text x="60" y="302" class="n" style="font-size:12.5px;fill:{FAINT}">before: 3 runs (7/12 · 7/10 · 6/10)</text>
<text x="400" y="302" class="n" style="font-size:12.5px;fill:{FAINT}">after: 1 run of 12</text>
"""
    return svg(W, H, "Results",
               "Baseline (unpatched) runs: 20 of 32 mode switches ended in a retrain; with the patch, 0 of 12.", css, body)

# ---------------------------------------------------------------- updates
def updates():
    W, H = 800, 250
    xs = [85, 211, 337, 463, 589, 715]
    names = ["new kernel", "exact source", "apply patch", "build i915", "validate", "install"]
    css = f"""
  .mk{{animation:walk 12s ease-in-out infinite}}
  @keyframes walk{{0%,6%{{transform:translateX(0)}}18%,24%{{transform:translateX(126px)}}36%,42%{{transform:translateX(252px)}}54%,60%{{transform:translateX(378px)}}72%,78%{{transform:translateX(504px)}}90%,100%{{transform:translateX(630px)}}}}
  .mkh{{animation:halo 2.4s ease-in-out infinite;transform-box:fill-box;transform-origin:center}}
  @keyframes halo{{0%,100%{{transform:scale(1);opacity:.9}}50%{{transform:scale(1.22);opacity:.55}}}}
  .note{{animation:sway 5s ease-in-out infinite}}
  @keyframes sway{{0%,100%{{transform:translateY(0)}}50%{{transform:translateY(2px)}}}}
"""
    parts = ""
    for i, (x, lab) in enumerate(zip(xs, names)):
        parts += (f'<path d="{wob(x - 28, 62, 56, 56, r=28, j=1.6, seed=60 + i)}" fill="{CREAM}" stroke="{INK}" stroke-width="3"/>'
                  f'<text x="{x}" y="97" text-anchor="middle" class="t" style="font-size:19px">{i + 1}</text>'
                  f'<text x="{x}" y="146" text-anchor="middle" class="s" style="font-size:14.5px">{lab}</text>')
    links = "".join(f'<path d="M {xs[i] + 34} 90 Q {xs[i] + 63} 84 {xs[i + 1] - 34} 90" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>'
                    f'<path d="M {xs[i + 1] - 42} 84 L {xs[i + 1] - 34} 90 L {xs[i + 1] - 42} 97" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>'
                    for i in range(5))
    body = f"""
<text x="44" y="40" class="n" style="font-size:18px">when a new kernel arrives</text>
<g class="mk"><circle class="mkh" cx="{xs[0]}" cy="90" r="40" fill="{AMBER_L}" opacity=".9"/></g>
<g filter="url(#r5)">{parts}{links}</g>
<g class="note">
  <path d="M {xs[4]} 156 Q {xs[4] - 12 } 170 {xs[4] - 60} 178" fill="none" stroke="{ROSE}" stroke-width="3" stroke-dasharray="3 8" stroke-linecap="round"/>
  <path d="{wob(120, 178, 560, 44, r=14, j=1.4, seed=77)}" fill="#F7DDD4" stroke="{ROSE}" stroke-width="2.8"/>
  <path d="M 146 200 L 158 212 M 158 200 L 146 212" stroke="{TERRA}" stroke-width="4" stroke-linecap="round"/>
  <text x="176" y="206" class="t" style="font-size:15.5px">if anything fails: nothing is installed, the stock driver stays</text>
</g>
"""
    return svg(W, H, "Automatic rebuild",
               "A new kernel triggers a pipeline: exact source, apply patch, build i915, validate, install; any failure installs nothing.",
               css, body, rough_filter("r5", 14))

# ---------------------------------------------------------------- squiggle (shared)
def squiggle():
    W, H = 800, 24
    css = f"""
  .sq{{stroke-dasharray:7 11;animation:sw 7s linear infinite}}
  @keyframes sw{{to{{stroke-dashoffset:-72}}}}
  @media (prefers-reduced-motion: reduce){{*{{animation:none!important}}}}
"""
    d = "M 10 12 " + " ".join("q 20 -9 40 0 t 40 0" for _ in range(9))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="">'
            f'<style>{css}</style><path class="sq" d="{d}" fill="none" stroke="{AMBER}" stroke-width="3.5" stroke-linecap="round"/></svg>\n')

def main():
    for name, fn in (("hero", hero), ("loop", loop), ("bit", bit), ("result", result), ("updates", updates), ("squiggle", squiggle)):
        with open(os.path.join(HERE, f"{name}.svg"), "w", encoding="utf-8") as f:
            f.write(fn())
    print("SVGs written to", HERE)

if __name__ == "__main__":
    main()
