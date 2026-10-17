#!/usr/bin/env python3
"""Render anonymized Kite UI reference screenshots for README and Fastlane."""

from html import escape
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "metadata/en-US/images/phoneScreenshots"
BG, FG, MUTED, SURFACE, PURPLE = "#faf7ff", "#24222a", "#77747e", "#f3eff9", "#e5d6ff"


def text(x, y, value, size=44, color=FG, weight=400, anchor="start"):
    return (f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" '
            f'font-weight="{weight}" text-anchor="{anchor}">{escape(value)}</text>')


def rect(x, y, width, height, color, radius=0):
    return f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" fill="{color}"/>'


def circle(x, y, radius, color):
    return f'<circle cx="{x}" cy="{y}" r="{radius}" fill="{color}"/>'


def base():
    elements = [rect(0, 0, 1080, 2340, BG), text(47, 75, "5:57", 40, weight=500)]
    # Neutral, synthetic status/navigation bars; no personal device state.
    elements += [text(785, 75, "●  ◉  ▂▄▆", 32, MUTED), rect(942, 38, 77, 38, MUTED, 20),
                 text(981, 67, "80", 28, "#ffffff", anchor="middle"),
                 rect(242, 2252, 9, 48, MUTED), rect(258, 2252, 9, 48, MUTED),
                 rect(274, 2252, 9, 48, MUTED),
                 f'<circle cx="540" cy="2277" r="21" fill="none" stroke="{MUTED}" stroke-width="5"/>',
                 f'<path d="M833 2253 L806 2278 L833 2301" fill="none" stroke="{MUTED}" stroke-width="5"/>']
    return elements


def avatar(x, y, label, color, radius=65):
    return [circle(x, y, radius, color), text(x, y + 16, label, 43, "#ffffff", 700, "middle")]


def inbox():
    elements = base()
    rooms = [
        ("DT", "#5d6b9f", "Design Team · Matrix", "Release checklist is ready", "17:52"),
        ("A", "#9061a1", "Alex · Matrix", "The new layout looks great", "16:44"),
        ("K", "#275e9f", "Kite Contributors · Matrix", "Screenshots are ready for review", "15:31"),
        ("B", "#2d7b70", "Build Bot · Matrix", "All checks completed", "14:12"),
        ("F", "#b56d59", "Friends · Matrix", "See you tomorrow!", "12:15"),
        ("C", "#5c5b8c", "Community · Matrix", "Welcome to the room", "Yesterday"),
        ("S", "#4c809d", "Sam · Matrix", "Can we try the latest build?", "Yesterday"),
        ("SU", "#946369", "Support · Matrix", "Thanks for the feedback", "Monday"),
    ]
    for i, (initial, color, name, preview, time) in enumerate(rooms):
        y = 225 + i * 235
        elements += avatar(120, y, initial, color)
        elements += [text(220, y - 12, name, 43), text(220, y + 56, preview, 36, MUTED),
                     text(1010, y - 22, time, 28, MUTED, anchor="end")]
    elements += [rect(45, 1982, 990, 170, SURFACE, 90),
                 f'<circle cx="115" cy="2053" r="23" stroke="{MUTED}" stroke-width="5" fill="none"/>',
                 f'<path d="M131 2070 L153 2094" stroke="{MUTED}" stroke-width="5"/>',
                 text(182, 2080, "Search", 43, MUTED)]
    elements += avatar(950, 2067, "K", "#61649a")
    return elements


def conversation():
    elements = base()
    elements += [f'<path d="M98 158 H59 L82 135 M59 158 L82 181" fill="none" stroke="{FG}" stroke-width="6"/>']
    elements += avatar(204, 171, "A", "#9061a1")
    elements += [text(295, 179, "Alex · Matrix", 45)]
    messages = [
        (32, 310, 823, 187, False, ["I pushed the latest build.", "Can you check it?"]),
        (188, 560, 840, 186, True, ["Looks much faster now.", "The layout feels great."]),
        (32, 805, 902, 186, False, ["Nice! We should share", "screenshots for the release."]),
        (216, 1058, 812, 188, True, ["I will add those to the", "release notes."]),
        (32, 1303, 860, 190, False, ["Thanks! It should be ready", "for testers soon."]),
    ]
    for x, y, width, height, outgoing, lines in messages:
        elements += [rect(x, y, width, height, PURPLE if outgoing else SURFACE, 38)]
        elements += [text(x + 34, y + 66, line, 43) for line in lines[:1]]
        elements += [text(x + 34, y + 123, line, 43) for line in lines[1:]]
    elements += [rect(45, 1982, 990, 168, SURFACE, 90),
                 text(92, 2088, "+", 56, MUTED), text(205, 2083, "Message", 43, MUTED),
                 f'<rect x="890" y="2031" width="54" height="62" rx="4" fill="none" stroke="{MUTED}" stroke-width="5"/>',
                 f'<path d="M902 2080 L917 2060 L929 2075 L944 2050" fill="none" stroke="{MUTED}" stroke-width="4"/>']
    return elements


def write_png(name, elements):
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="2340" '
           'viewBox="0 0 1080 2340"><g font-family="Roboto, sans-serif">'
           + "".join(elements) + "</g></svg>")
    dest = DEST / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "--format", "png", "--output", str(dest)],
                   input=svg, text=True, check=True)
    if dest.stat().st_size < 10000:
        raise RuntimeError(f"Screenshot appears empty: {dest}")
    print(dest.relative_to(ROOT))


if __name__ == "__main__":
    write_png("1_en-US.png", inbox())
    write_png("2_en-US.png", conversation())
