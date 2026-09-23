#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
VARIANTS_DIR = ROOT / "assets" / "branding" / "icon_variants"
ANDROID_MAIN = ROOT / "android" / "app" / "src"
VIEWBOX = 1080
BG = "#003197"

variants = [
    {"id":"icon01","name":"Folded K","background":BG,"shapes":[
        {"d":"M270 205 Q245 205 245 235 L245 845 Q245 875 275 875 H365 V690 L480 585 L395 500 L365 525 V205 Z","fill":"#8EC4FD"},
        {"d":"M395 500 L690 205 H865 L585 515 L480 585 Z","fill":"#8E81FD"},
        {"d":"M480 585 L585 515 L865 875 H690 Z","fill":"#494FE8"}]},
    {"id":"icon02","name":"Facet Kite","background":BG,"shapes":[
        {"d":"M540 150 L540 500 L205 500 Z","fill":"#8EC4FD"},{"d":"M540 150 L875 500 L540 500 Z","fill":"#8E81FD"},
        {"d":"M875 500 L540 850 L540 500 Z","fill":"#494FE8"},{"d":"M205 500 L540 850 L540 500 Z","fill":"#2F6AE6"},
        {"d":"M540 850 L650 940 L565 915 L515 965 L500 885 Z","fill":"#8EC4FD"}]},
    {"id":"icon03","name":"Twin Wing","background":BG,"shapes":[
        {"d":"M245 210 Q245 185 270 185 H355 Q380 185 380 210 V870 H245 Z","fill":"#8EC4FD"},
        {"d":"M380 535 L760 190 H900 L600 545 Z","fill":"#8E81FD"},{"d":"M380 535 L600 545 L900 880 H735 Z","fill":"#494FE8"},
        {"d":"M380 535 L505 455 L585 545 L505 635 Z","fill":"#65D8FF"}]},
    {"id":"icon04","name":"Prism Chevron","background":BG,"shapes":[
        {"d":"M185 540 L470 205 H620 L345 540 L620 875 H470 Z","fill":"#8EC4FD"},
        {"d":"M390 540 L665 205 H835 L560 540 L835 875 H665 Z","fill":"#8E81FD"},
        {"d":"M595 540 L785 310 L900 450 L825 540 L900 630 L785 770 Z","fill":"#494FE8"}]},
    {"id":"icon05","name":"Ribbon Knot","background":BG,"shapes":[
        {"d":"M245 205 H390 V875 H245 Z","fill":"#8EC4FD"},{"d":"M390 475 L690 205 H870 L565 520 L465 610 L390 545 Z","fill":"#8E81FD"},
        {"d":"M465 610 L565 520 L870 875 H690 Z","fill":"#494FE8"},{"d":"M390 475 L520 590 L465 610 L390 545 Z","fill":"#65D8FF"}]},
    {"id":"icon06","name":"Compass Kite","background":"#071F5C","shapes":[
        {"d":"M540 145 L655 420 L540 500 L425 420 Z","fill":"#8EC4FD"},{"d":"M935 540 L660 655 L580 540 L660 425 Z","fill":"#8E81FD"},
        {"d":"M540 935 L425 660 L540 580 L655 660 Z","fill":"#494FE8"},{"d":"M145 540 L420 425 L500 540 L420 655 Z","fill":"#2F6AE6"},
        {"d":"M540 420 L660 540 L540 660 L420 540 Z","fill":"#65D8FF"}]},
    {"id":"icon07","name":"Bolt K","background":BG,"shapes":[
        {"d":"M285 185 H430 V455 L650 185 H835 L575 505 L455 600 L430 580 V875 H285 Z","fill":"#8EC4FD"},
        {"d":"M455 600 L575 505 L865 875 H680 Z","fill":"#8E81FD"},{"d":"M650 185 H835 L575 505 L505 560 L555 385 Z","fill":"#494FE8"}]},
    {"id":"icon08","name":"Split Monogram","background":BG,"shapes":[
        {"d":"M225 190 H390 V890 H225 Z","fill":"#8EC4FD"},{"d":"M390 540 L700 190 H900 L585 540 Z","fill":"#8E81FD"},
        {"d":"M390 540 H585 L900 890 H700 Z","fill":"#494FE8"},{"d":"M390 465 L470 540 L390 615 Z","fill":"#65D8FF"}]},
    {"id":"icon09","name":"Paper Kite","background":BG,"shapes":[
        {"d":"M320 185 L560 480 L220 620 Z","fill":"#8EC4FD"},{"d":"M320 185 L865 365 L560 480 Z","fill":"#8E81FD"},
        {"d":"M865 365 L560 875 L560 480 Z","fill":"#494FE8"},{"d":"M220 620 L560 875 L560 480 Z","fill":"#2F6AE6"},
        {"d":"M560 875 L680 935 L610 950 L555 915 L500 960 L465 920 Z","fill":"#8EC4FD"}]},
    {"id":"icon10","name":"Orbital K","background":"#071F5C","shapes":[
        {"d":"M300 235 H420 V485 L650 235 H825 L560 525 L420 650 V845 H300 Z","fill":"#8EC4FD"},
        {"d":"M500 590 L575 520 L830 845 H665 Z","fill":"#8E81FD"},
        {"d":"M175 540 C175 330 335 175 540 175 C745 175 905 330 905 540 C905 750 745 905 540 905","fill":"none","stroke":"#494FE8","stroke_width":42},
        {"d":"M540 905 L475 855 L565 835 Z","fill":"#494FE8"}]},
]

def svg_path(shape, monochrome=False):
    fill = "#FFFFFF" if monochrome and shape.get("fill") != "none" else shape.get("fill", "none")
    stroke = "#FFFFFF" if monochrome and shape.get("stroke") else shape.get("stroke")
    attrs = [f'd="{shape["d"]}"', f'fill="{fill}"']
    if stroke:
        attrs += [f'stroke="{stroke}"', f'stroke-width="{shape.get("stroke_width", 1)}"', 'stroke-linecap="round"', 'stroke-linejoin="round"']
    return "<path " + " ".join(attrs) + "/>"

def full_svg(variant):
    shapes = "\n  ".join(svg_path(s) for s in variant["shapes"])
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {VIEWBOX} {VIEWBOX}">
  <rect width="{VIEWBOX}" height="{VIEWBOX}" rx="220" fill="{variant["background"]}"/>
  {shapes}
</svg>
'''

def foreground_svg(variant):
    shapes = "\n  ".join(svg_path(s) for s in variant["shapes"])
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {VIEWBOX} {VIEWBOX}">
  {shapes}
</svg>
'''

def vector_xml(variant, monochrome=False):
    paths = []
    for s in variant["shapes"]:
        fill = "#FFFFFFFF" if monochrome and s.get("fill") != "none" else s.get("fill", "none")
        attrs = ['android:fillColor="#00000000"' if fill == "none" else f'android:fillColor="{fill}"']
        if s.get("stroke"):
            stroke = "#FFFFFFFF" if monochrome else s["stroke"]
            attrs += [f'android:strokeColor="{stroke}"', f'android:strokeWidth="{s.get("stroke_width", 1)}"', 'android:strokeLineCap="round"', 'android:strokeLineJoin="round"']
        attrs.append(f'android:pathData="{s["d"]}"')
        paths.append("    <path " + " ".join(attrs) + " />")
    return f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="{VIEWBOX}"
    android:viewportHeight="{VIEWBOX}">
{chr(10).join(paths)}
</vector>
'''

def render(svg, png, size):
    png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert","--width",str(size),"--height",str(size),"--output",str(png),str(svg)], check=True)

def contact_sheet():
    cell, gap = 280, 26
    width = gap + 5 * (cell + gap)
    height = gap + 2 * (cell + 64 + gap)
    groups = []
    for i, v in enumerate(variants):
        row, col = divmod(i, 5)
        x = gap + col * (cell + gap)
        y = gap + row * (cell + 64 + gap)
        icon = full_svg(v).split(">", 1)[1].rsplit("</svg>", 1)[0]
        groups.append(f'<g transform="translate({x} {y}) scale({cell/VIEWBOX})">{icon}</g>')
        groups.append(f'<text x="{x + cell/2}" y="{y + cell + 35}" text-anchor="middle" font-family="sans-serif" font-size="24" font-weight="700" fill="#0A1633">{i+1:02d} · {v["name"]}</text>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">
  <rect width="100%" height="100%" fill="#F4F7FC"/>
  {chr(10).join(groups)}
</svg>
'''

def main():
    VARIANTS_DIR.mkdir(parents=True, exist_ok=True)
    densities = {"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}
    for variant in variants:
        variant_id = variant["id"]
        svg = VARIANTS_DIR / f"{variant_id}.svg"
        fg = VARIANTS_DIR / f"{variant_id}_foreground.svg"
        svg.write_text(full_svg(variant))
        fg.write_text(foreground_svg(variant))
        res = ANDROID_MAIN / variant_id / "res"
        (res / "drawable").mkdir(parents=True, exist_ok=True)
        (res / "values").mkdir(parents=True, exist_ok=True)
        (res / "drawable" / "ic_launcher_foreground.xml").write_text(vector_xml(variant))
        (res / "drawable" / "ic_launcher_monochrome.xml").write_text(vector_xml(variant, monochrome=True))
        (res / "values" / "colors.xml").write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{variant["background"]}</color>
</resources>
''')
        for density, size in densities.items():
            render(svg, res / f"mipmap-{density}" / "ic_launcher.png", size)
    preview_svg = VARIANTS_DIR / "preview.svg"
    preview_png = VARIANTS_DIR / "preview.png"
    preview_svg.write_text(contact_sheet())
    subprocess.run(["rsvg-convert","--output",str(preview_png),str(preview_svg)], check=True)
    (VARIANTS_DIR / "README.md").write_text(
        "# Kite icon redesigns\n\n"
        "Ten launcher-scale concepts for Samsung/Android comparison. The APK flavors are icon01 through icon10 "
        "and use distinct application IDs so they can be installed together.\n\n"
        + "\n".join(f"- {v['id']} — {v['name']}" for v in variants) + "\n"
    )

if __name__ == "__main__":
    main()
