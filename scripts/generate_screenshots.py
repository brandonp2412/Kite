#!/usr/bin/env python3
"""Deterministic, fictional Kite UI gallery and eight curated store images."""

import argparse
from dataclasses import dataclass
from html import escape
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "metadata/en-US/images/phoneScreenshots"
GALLERY = ROOT / "screenshots/generated"
SIZE = (1080, 2340)


@dataclass(frozen=True)
class Colors:
    bg: str
    ink: str
    subtle: str
    panel: str
    faint: str
    accent: str
    accent_ink: str
    outline: str


THEMES = {
    "light": Colors("#FCFAFF", "#25222C", "#77727F", "#F2EFF8", "#F9F6FC", "#E7D9FF", "#6439A6", "#E7E2ED"),
    "dark": Colors("#15131B", "#F4F0F8", "#ABA5B4", "#282430", "#211E27", "#51406C", "#DEC7FF", "#383341"),
}


class Screen:
    def __init__(self, theme):
        self.c = THEMES[theme]
        self.parts = []
        self.rect(0, 0, *SIZE, self.c.bg)
        self.text(50, 74, "9:41", 40, weight=600)
        self.text(830, 74, "●  ◉  ▂▄▆", 30, color=self.c.subtle)
        self.rect(972, 42, 63, 27, self.c.subtle, 8)
        self.rect(995, 48, 32, 15, self.c.bg, 4)

    def rect(self, x, y, w, h, fill, radius=0, stroke=None):
        border = f' stroke="{stroke}" stroke-width="2"' if stroke else ""
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}"{border}/>')

    def circle(self, x, y, r, fill):
        self.parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"/>')

    def text(self, x, y, value, size=42, color=None, weight=400, anchor="start"):
        self.parts.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{color or self.c.ink}" font-weight="{weight}" text-anchor="{anchor}">{escape(str(value))}</text>')

    def line(self, x1, y1, x2, y2, color=None, width=4):
        self.parts.append(f'<path d="M{x1} {y1} L{x2} {y2}" fill="none" stroke="{color or self.c.ink}" stroke-width="{width}" stroke-linecap="round"/>')

    def avatar(self, x, y, initials, color="#7667B2", size=57):
        self.circle(x, y, size, color)
        self.text(x, y + 14, initials, 35 if len(initials) > 1 else 43, "#FFFFFF", 650, "middle")

    def icon(self, x, y, name, color=None, scale=1.0):
        paths = {
            "back": "M18 4 L6 16 L18 28", "search": "M13 24 A11 11 0 1 1 24 13 M21 21 L31 31",
            "more": "M5 16 h1 M16 16 h1 M27 16 h1", "plus": "M16 3 V29 M3 16 H29",
            "send": "M3 5 L30 16 L3 27 L8 17 L20 16 L8 15 Z", "check": "M3 15 L12 24 L29 6",
            "photo": "M4 4 H28 V28 H4 Z M6 23 L14 14 L19 19 L23 12 L28 19",
            "settings": "M16 4 V0 M16 32 V28 M4 16 H0 M32 16 H28 M7 7 L4 4 M28 28 L25 25 M25 7 L28 4 M4 28 L7 25 M16 9 A7 7 0 1 1 15.99 9",
            "lock": "M7 14 H25 V29 H7 Z M11 14 V9 A5 5 0 0 1 21 9 V14",
            "reply": "M14 9 L4 17 L14 25 M4 17 H21 Q29 17 29 26",
            "play": "M9 4 L27 16 L9 28 Z", "bell": "M7 23 L11 18 V12 A5 5 0 0 1 21 12 V18 L25 23 Z",
            "moon": "M25 4 A12 12 0 1 0 28 25 A13 13 0 0 1 25 4",
        }
        d = paths.get(name, paths["more"])
        self.parts.append(f'<g transform="translate({x} {y}) scale({scale})"><path d="{d}" fill="none" stroke="{color or self.c.ink}" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round"/></g>')

    def pill(self, x, y, label, selected=False, width=None):
        w = width or max(96, len(label) * 23 + 55)
        self.rect(x, y, w, 80, self.c.accent if selected else self.c.panel, 40)
        self.text(x + w / 2, y + 53, label, 34, self.c.accent_ink if selected else self.c.ink, 550, "middle")
        return w

    def header(self, title, subtitle=None, back=False, avatar=None):
        if back:
            self.icon(40, 142, "back", scale=1.25)
        x = 142 if back else 54
        if avatar:
            self.avatar(x + 30, 174, avatar, size=49)
            x += 103
        self.text(x, 187 if not subtitle else 169, title, 55 if not subtitle else 45, weight=650)
        if subtitle:
            self.text(x, 216, subtitle, 31, self.c.subtle)
        self.icon(984, 145, "more", scale=1.2)
        self.line(42, 247, 1038, 247, self.c.outline, 2)

    def footer(self, text="Search", search=True):
        y = 2043
        self.rect(32, y, 1016, 142, self.c.panel, 71)
        if search:
            self.icon(82, y + 50, "search", self.c.subtle, 1.35)
            self.text(164, y + 92, text, 43, self.c.subtle)
            self.avatar(969, y + 72, "K", "#655B9C", 49)
        else:
            self.icon(76, y + 52, "plus", self.c.subtle, 1.3)
            self.text(179, y + 92, text, 43, self.c.subtle)
            self.icon(944, y + 50, "photo", self.c.subtle, 1.3)

    def finish(self):
        self.rect(435, 2264, 210, 13, self.c.subtle, 7)
        return '<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="2340" viewBox="0 0 1080 2340"><g font-family="Roboto,Inter,Noto Sans,sans-serif">' + "".join(self.parts) + "</g></svg>"


PEOPLE = [
    ("DT", "#6778AE", "Design Team", "Maya: Can you review the new icons?", "9:36", 2),
    ("AL", "#9267AF", "Alex", "Love that idea! ✨", "9:31", 0),
    ("FR", "#C17A6A", "Friday Plans", "Sam: Table booked for seven", "8:55", 3),
    ("SA", "#4C8F88", "Sam", "See you there!", "Yesterday", 0),
    ("CM", "#8B78C0", "Community", "New messages since yesterday", "Yesterday", 1),
    ("BO", "#557BA1", "Build Bot", "All checks passed ✓", "Monday", 0),
    ("JP", "#B67A97", "Jordan", "Sent a photo", "Monday", 0),
]


def inbox(s, state):
    s.header("Kite")
    x = 46
    for label in ["All", "Unread", "Groups", "People"]:
        x += s.pill(x, 281, label, state == label.lower() or (state == "all" and label == "All")) + 18
    if state in {"empty", "offline", "syncing"}:
        s.circle(540, 900, 165, s.c.panel)
        s.icon(510, 867, "search" if state == "empty" else "bell", s.c.accent_ink, 2)
        s.text(540, 1140, {"empty": "Your conversations appear here", "offline": "You're offline", "syncing": "Getting everything ready…"}[state], 50, weight=600, anchor="middle")
        s.text(540, 1215, "All your chats, in one calm place", 35, s.c.subtle, anchor="middle")
    else:
        rows = PEOPLE
        if state == "unread": rows = [x for x in PEOPLE if x[-1]]
        if state == "groups": rows = [PEOPLE[i] for i in (0, 2, 4, 5)]
        if state == "people": rows = [PEOPLE[i] for i in (1, 3, 6)]
        if state == "pinned": rows = [PEOPLE[i] for i in (1, 0, 2, 3, 4, 5, 6)]
        if state == "busy": rows = PEOPLE + PEOPLE[:1]
        for i, (initials, color, name, preview, time, unread) in enumerate(rows):
            y = 446 + i * 221
            if y > 1915: break
            if i < 2 and state == "pinned": s.rect(30, y - 92, 1020, 192, s.c.faint, 30)
            s.avatar(119, y, initials, color, 66)
            s.text(224, y - 12, name, 43, weight=630 if unread else 500)
            s.text(224, y + 51, preview, 34, s.c.subtle)
            s.text(1032, y - 31, time, 28, s.c.subtle, anchor="end")
            if unread:
                s.circle(993, y + 38, 23, s.c.accent_ink)
                s.text(993, y + 49, unread, 26, s.c.bg, 650, "middle")
    s.footer()


def bubble(s, x, y, lines, outgoing=False, width=760, height=None, reaction=None):
    height = height or 70 + 52 * len(lines)
    s.rect(x, y, width, height, s.c.accent if outgoing else s.c.panel, 39)
    for j, line in enumerate(lines): s.text(x + 31, y + 59 + j * 54, line, 39)
    if reaction:
        w = 148
        s.rect(x + 21, y + height - 9, w, 70, s.c.faint, 35, s.c.outline)
        s.text(x + 94, y + height + 38, reaction, 39, anchor="middle")


def landscape(s, x, y, w, h):
    s.rect(x, y, w, h, "#83B9C5", 33)
    s.circle(x + w * .74, y + h * .26, 58, "#FFE1A5")
    s.parts.append(f'<path d="M{x} {y+h*.8} L{x+w*.28} {y+h*.35} L{x+w*.49} {y+h*.72} L{x+w*.71} {y+h*.45} L{x+w} {y+h*.82} V{y+h-26} Q{x+w} {y+h} {x+w-28} {y+h} H{x+28} Q{x} {y+h} {x} {y+h-28} Z" fill="#476F91"/>')
    s.parts.append(f'<path d="M{x} {y+h*.88} L{x+w*.34} {y+h*.6} L{x+w*.52} {y+h*.9} L{x+w*.78} {y+h*.68} L{x+w} {y+h*.92} V{y+h-28} Q{x+w} {y+h} {x+w-28} {y+h} H{x+28} Q{x} {y+h} {x} {y+h-28} Z" fill="#416F66"/>')


def conversation(s, state):
    group = state in {"group", "poll", "thread", "members", "unread"}
    s.header("Design Team" if group else "Alex", "6 members · encrypted" if group else "Online · encrypted", True, "DT" if group else "AL")
    s.text(540, 322, "TODAY", 29, s.c.subtle, 550, "middle")
    bubble(s, 39, 375, ["Hey! How's the new build", "looking on your phone?"], width=730)
    bubble(s, 238, 607, ["Really smooth so far.", "The new layout feels great."], True, 803)
    if group:
        s.avatar(80, 926, "M", "#C47992", 36)
        s.text(129, 906, "Maya", 31, s.c.subtle)
        bubble(s, 129, 928, ["Could everyone review", "the design before Friday?"], width=790, reaction="❤️  3")
    else:
        bubble(s, 39, 875, ["I've shared some fresh", "screenshots with you 😊"], width=797, reaction="❤️  2")
    if state in {"media", "image", "video", "gallery"}:
        landscape(s, 253, 1197, 756, 595)
        if state == "video":
            s.circle(630, 1493, 73, "#51406C")
            s.icon(611, 1470, "play", "#FFFFFF", 1.4)
    elif state == "voice":
        s.rect(232, 1308, 802, 177, s.c.accent, 45)
        s.icon(274, 1351, "play", scale=2)
        for k, h in enumerate([35, 71, 45, 92, 58, 100, 67, 38, 83, 60, 42, 91, 72, 52, 68]):
            s.rect(371 + k * 34, 1412 - h / 2, 10, h, s.c.accent_ink, 5)
        s.text(944, 1415, "0:24", 31, s.c.ink, anchor="end")
    elif state == "file":
        s.rect(231, 1288, 795, 225, s.c.accent, 42)
        s.rect(273, 1340, 115, 126, s.c.faint, 25)
        s.text(330, 1417, "PDF", 36, s.c.accent_ink, 700, "middle")
        s.text(418, 1387, "Design-notes.pdf", 42, weight=600)
        s.text(418, 1440, "1.2 MB · Document", 31, s.c.subtle)
    elif state == "poll":
        s.rect(126, 1260, 823, 513, s.c.panel, 42)
        s.text(170, 1342, "When should we meet?", 44, weight=600)
        for i, (lbl, pct) in enumerate([("Thursday", 76), ("Friday", 47), ("Saturday", 22)]):
            y = 1394 + i * 113
            s.rect(171, y, 724, 83, s.c.faint, 29)
            s.rect(171, y, pct * 7, 83, s.c.accent, 29)
            s.text(199, y + 54, lbl, 35)
            s.text(864, y + 54, f"{pct}%", 31, s.c.subtle, anchor="end")
    elif state in {"reply", "thread"}:
        s.rect(204, 1268, 809, 311, s.c.accent, 42)
        s.rect(234, 1299, 8, 172, s.c.accent_ink, 3)
        s.text(268, 1350, "Alex · replied to Maya", 33, s.c.accent_ink, 600)
        s.text(268, 1418, "The earlier layout was lovely", 33, s.c.subtle)
        s.text(248, 1531, "This is even better! 🎉", 41)
    else:
        bubble(s, 228, 1317, ["It's looking fantastic.", "Let's ship it! 🚀"], True, 806)
    if state == "reactions":
        s.rect(56, 1570, 965, 166, s.c.faint, 73, s.c.outline)
        for j, em in enumerate(["❤️", "👍", "😂", "😮", "😢", "＋"]): s.text(119 + j * 158, 1672, em, 58, anchor="middle")
        s.rect(190, 1754, 730, 176, s.c.panel, 36)
        for j, action in enumerate(["Reply", "Copy", "Select", "More"]): s.text(276 + j * 171, 1858, action, 33, anchor="middle")
    elif state == "selection":
        s.rect(23, 1260, 1035, 475, s.c.faint, 36, s.c.outline)
        s.circle(81, 1520, 35, s.c.accent_ink)
        s.icon(65, 1500, "check", "#FFFFFF", 1.1)
        s.rect(0, 1860, 1080, 160, s.c.panel)
        s.text(67, 1955, "1 selected", 43, weight=600)
        s.text(720, 1955, "Copy    Reply", 35)
    elif state == "typing":
        s.rect(44, 1802, 265, 98, s.c.panel, 49)
        s.text(178, 1869, "●  ●  ●", 35, s.c.subtle, anchor="middle")
    elif state == "failed":
        s.text(1017, 1650, "Not sent · Retry", 31, "#C94D58", anchor="end")
    elif state == "unread":
        s.rect(22, 1773, 1036, 84, s.c.accent, 42)
        s.text(540, 1828, "New messages", 34, s.c.accent_ink, 550, "middle")
    if state == "composer":
        s.rect(42, 1920, 995, 95, s.c.accent, 38)
        s.text(92, 1984, "Replying to Alex · Lovely!", 35, s.c.accent_ink)
    if state == "attached": landscape(s, 70, 1670, 337, 285)
    s.footer("Write a message…", False)


def search(s, state):
    s.header("Search", back=True)
    query = {"empty": "No results for 'xyzzy'", "media": "Photos and files", "people": "People", "rooms": "Groups", "all": "design", "messages": "design", "recent": "Recent searches"}.get(state, "design")
    s.rect(35, 284, 1010, 120, s.c.panel, 54)
    s.icon(81, 326, "search", s.c.subtle, 1.5)
    s.text(166, 360, query if state not in {"empty", "recent"} else "Search messages and people", 39, s.c.subtle)
    x = 45
    for label in ["All", "Messages", "People", "Media"]:
        x += s.pill(x, 444, label, (state == label.lower() or (state in {"recent", "rooms"} and label == "All"))) + 14
    if state == "empty":
        s.text(540, 1020, "No matches yet", 52, weight=600, anchor="middle")
        s.text(540, 1090, "Try a different search term", 34, s.c.subtle, anchor="middle")
    else:
        s.text(58, 604, "RESULTS" if state != "recent" else "RECENTS", 32, s.c.subtle, 600)
        for i, (initials, color, name, preview, _, _) in enumerate(PEOPLE[:6]):
            if state == "people" and i > 3: break
            if state == "media": break
            y = 725 + i * 206
            s.avatar(110, y, initials, color)
            s.text(214, y - 9, name, 42, weight=600)
            s.text(214, y + 46, preview if state not in {"people", "recent"} else "matrix.org", 34, s.c.subtle)
        if state == "media":
            for i in range(9): landscape(s, 49 + i % 3 * 338, 658 + i // 3 * 435, 310, 386)
    s.footer("Search", True)


def settings(s, state):
    s.header("Settings", back=True)
    sections = {
        "general": [("Your accounts", "Signed in and syncing"), ("Appearance", "Themes, colours, and layout"), ("Conversations", "Message actions and gestures"), ("Notifications", "Choose what notifies you"), ("Privacy & security", "Encryption and account data"), ("About Kite", "An open Matrix client")],
        "appearance": [("Theme", "System default"), ("Dark mode", "Follow device setting"), ("Bubble style", "Rounded"), ("Text size", "Default"), ("Chat list", "Compact previews off"), ("High contrast", "Disabled")],
        "notifications": [("Direct messages", "On"), ("Group chats", "Mentions only"), ("Message previews", "Show content"), ("Sounds", "Default"), ("Vibration", "On"), ("Quiet hours", "Not configured")],
        "conversation": [("Double-tap reaction", "Heart ❤️"), ("Swipe to reply", "On"), ("Show read receipts", "On"), ("Message action shortcuts", "Enabled"), ("Send on Enter", "On"), ("Media previews", "On")],
        "privacy": [("End-to-end encryption", "Enabled in encrypted rooms"), ("Device verification", "Review sessions"), ("Read receipts", "Enabled"), ("Link previews", "Ask before loading"), ("Blocked users", "None"), ("Secure storage", "On-device")],
        "accessibility": [("Text size", "Large"), ("High contrast", "Off"), ("Reduce motion", "On"), ("Touch targets", "Standard"), ("Screen reader labels", "Enabled")],
    }
    title = "Settings" if state == "general" else {"appearance": "Appearance", "notifications": "Notifications", "conversation": "Conversations", "privacy": "Privacy & security", "accessibility": "Accessibility"}[state]
    s.text(50, 352, title, 60, weight=700)
    if state == "appearance":
        s.rect(50, 420, 978, 294, s.c.panel, 44)
        s.rect(101, 463, 393, 205, "#ECE4FD", 33)
        s.rect(558, 463, 409, 205, "#312743", 33)
        for i, col in enumerate(["#C6ABE9", "#DFCFF3", "#A789D4"]): s.rect(137, 510+i*47, 280, 27, col, 13)
        for i, col in enumerate(["#5A4479", "#655080", "#8C73AE"]): s.rect(603, 510+i*47, 290, 27, col, 13)
        start = 766
    else: start = 449
    for i, (name, desc) in enumerate(sections[state]):
        y = start + i * 223
        s.rect(41, y, 999, 184, s.c.panel, 37)
        s.text(80, y + 74, name, 42, weight=580)
        s.text(80, y + 129, desc, 32, s.c.subtle)
        s.text(976, y + 111, "›", 66, s.c.subtle, anchor="middle")


def accounts(s, state):
    s.header("Accounts", back=True)
    s.text(49, 362, "Stay connected everywhere", 52, weight=650)
    s.text(49, 428, "Your homeservers, in one inbox", 34, s.c.subtle)
    for i, (name, subtitle, initials, color) in enumerate([("Alex", "@alex:matrix.org", "AL", "#9267AF"), ("Kite Team", "@kite:example.org", "KT", "#6778AE")]):
        y = 530 + 250 * i
        s.rect(32, y, 1016, 201, s.c.panel, 35)
        s.avatar(115, y + 100, initials, color)
        s.text(220, y + 88, name, 44, weight=600)
        s.text(220, y + 146, subtitle, 34, s.c.subtle)
        if (i == 0 and state != "switch") or (i == 1 and state == "switch"):
            s.circle(971, y + 100, 31, s.c.accent_ink)
            s.icon(958, y + 86, "check", s.c.bg)
    if state == "profile":
        s.text(51, 1200, "Profile", 47, weight=600)
        s.rect(36, 1260, 1006, 335, s.c.panel, 40)
        s.avatar(182, 1420, "AL", "#9267AF", 81)
        s.text(319, 1397, "Alex", 50, weight=650)
        s.text(319, 1464, "Available · Matrix", 32, s.c.subtle)
    else:
        s.rect(40, 1141, 999, 141, s.c.faint, 42, s.c.outline)
        s.icon(82, 1197, "plus", s.c.accent_ink, 1.3)
        s.text(190, 1228, "Add another account", 41, s.c.accent_ink, 600)
    s.text(51, 1865, "Independent accounts. One convenient place.", 32, s.c.subtle)


def room(s, state):
    s.header("Design Team", "Room details", True, "DT")
    s.avatar(540, 435, "DT", "#6778AE", 125)
    s.text(540, 642, "Design Team", 56, weight=650, anchor="middle")
    s.text(540, 699, "6 members · Encrypted", 34, s.c.subtle, anchor="middle")
    tabs = ["Overview", "Members", "Media", "Files"]
    x = 35
    for name in tabs: x += s.pill(x, 777, name, (state == name.lower())) + 10
    if state == "members":
        for i, row in enumerate([("AL", "Alex"), ("MA", "Maya"), ("SA", "Sam"), ("JO", "Jordan"), ("KI", "Kite")]):
            y = 965 + i*195
            s.avatar(111, y, row[0], ["#9267AF", "#C47992", "#4C8F88", "#B67A97", "#6778AE"][i])
            s.text(221, y + 12, row[1], 44)
            s.text(221, y + 62, "Member" if i else "Admin", 31, s.c.subtle)
    elif state in {"media", "files"}:
        for i in range(9):
            if state == "media": landscape(s, 45+i%3*341, 925+i//3*340, 312, 302)
            else:
                y = 955 + i*160
                if y > 1900: break
                s.rect(45, y, 987, 135, s.c.panel, 30)
                s.text(95, y+86, "▤", 56, s.c.accent_ink)
                s.text(186, y+84, f"Design-notes-{i+1}.pdf", 39)
    else:
        for i, (label, desc) in enumerate([("Room address", "#design:example.org"), ("Notifications", "Mentions only"), ("Pinned messages", "2 messages"), ("Encryption", "Enabled")]):
            y = 940 + i*195
            s.rect(42, y, 993, 166, s.c.panel, 34)
            s.text(89, y+69, label, 40, weight=600)
            s.text(89, y+120, desc, 31, s.c.subtle)


def onboarding(s, state):
    s.text(540, 499, "Kite", 96, s.c.accent_ink, 700, "middle")
    s.text(540, 583, "Your space to connect", 45, s.c.subtle, anchor="middle")
    s.circle(540, 880, 172, s.c.accent)
    s.text(540, 918, "K", 143, s.c.accent_ink, 700, "middle")
    if state != "welcome":
        s.text(67, 1277, {"server":"Choose your homeserver", "login":"Sign in", "verify":"Verify this device"}[state], 48, weight=650)
        s.rect(54, 1375, 969, 124, s.c.panel, 32)
        s.text(87, 1455, {"server":"matrix.org", "login":"Username or email", "verify":"Recovery key"}[state], 38, s.c.subtle)
    s.rect(55, 1911, 965, 144, s.c.accent_ink, 58)
    s.text(540, 2002, "Get started" if state == "welcome" else "Continue", 44, s.c.bg, 650, "middle")


SCENES = {
    "inbox": (inbox, ["all", "unread", "groups", "people", "pinned", "busy", "empty", "offline", "syncing"]),
    "chat": (conversation, ["direct", "group", "reactions", "media", "video", "voice", "file", "poll", "reply", "thread", "selection", "typing", "failed", "unread", "composer", "attached"]),
    "search": (search, ["all", "messages", "people", "rooms", "media", "empty", "recent"]),
    "settings": (settings, ["general", "appearance", "notifications", "conversation", "privacy", "accessibility"]),
    "account": (accounts, ["switcher", "switch", "profile"]),
    "room": (room, ["overview", "members", "media", "files"]),
    "onboarding": (onboarding, ["welcome", "server", "login", "verify"]),
}

# Store ordering is editorial. All other variants stay in the gallery, not Play metadata.
CURATED = [
    "inbox-all-light", "chat-direct-light", "chat-poll-light", "chat-reactions-light",
    "chat-media-light", "search-all-light", "account-switcher-light", "settings-appearance-dark",
]


def render(svg, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "-f", "png", "-o", str(destination)], input=svg.encode(), check=True)
    if destination.stat().st_size < 10000:
        raise RuntimeError(f"Screenshot is suspiciously small: {destination}")


def write_gallery_index(names):
    cards = "".join(
        f'<a class="shot" data-name="{name}" href="generated/{name}.png">'
        f'<img loading="lazy" src="generated/{name}.png" alt="{name}">'
        f'<span>{name.replace("-", " ")}{" ★" if name in CURATED else ""}</span></a>'
        for name in [*CURATED, *(name for name in names if name not in CURATED)]
    )
    html = '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Kite screenshot gallery</title>
<style>body{background:#16141d;color:#eee9f8;font:16px system-ui;margin:0;padding:32px}
h1{margin:0 0 8px}p{color:#bcb5ca}input{font:inherit;padding:15px 20px;width:min(450px,90%);border:1px solid #635879;
border-radius:14px;background:#282333;color:white;margin:15px 0 28px}.grid{display:grid;grid-template-columns:
repeat(auto-fill,minmax(220px,1fr));gap:24px}.shot{color:inherit;text-decoration:none;background:#292533;
border-radius:20px;overflow:hidden}.shot img{width:100%;display:block}.shot span{display:block;padding:14px;
text-transform:capitalize;font-size:14px}.shot:hover{outline:3px solid #bda1ee}</style>
<h1>Kite screenshot library</h1><p>Fictional UI scenarios · the first eight starred entries are store selections.</p>
<input id="filter" type="search" placeholder="Filter by screen, state, or theme…"><main class="grid">'''
    html += cards + '''</main><script>document.getElementById('filter').addEventListener('input', e => {
const q=e.target.value.toLowerCase();document.querySelectorAll('.shot').forEach(el =>
el.hidden=!el.dataset.name.includes(q));});</script></html>'''
    (ROOT / "screenshots/index.html").write_text(html)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--store-only", action="store_true", help="Only render the selected eight")
    args = parser.parse_args()
    if not shutil.which("rsvg-convert"):
        sys.exit("Install librsvg (rsvg-convert) first")
    outputs = {}
    selected = set(CURATED)
    for family, (draw, states) in SCENES.items():
        for state in states:
            for theme in THEMES:
                key = f"{family}-{state}-{theme}"
                if args.store_only and key not in selected: continue
                s = Screen(theme)
                draw(s, state)
                svg = s.finish()
                path = GALLERY / f"{key}.png"
                if not args.store_only: render(svg, path)
                outputs[key] = svg
    assert len(CURATED) == 8 and len(selected) == 8 and selected <= outputs.keys()
    for i, key in enumerate(CURATED, 1):
        render(outputs[key], STORE / f"{i}_en-US.png")
    required = {f"{i}_en-US.png" for i in range(1, 9)}
    for old in STORE.glob("*_en-US.png"):
        if old.stem.removesuffix("_en-US").isdigit() and old.name not in required:
            old.unlink()
    actual = {file.name for file in STORE.glob("*.png")}
    if actual != required:
        raise RuntimeError(f"Store must contain exactly eight images, found {sorted(actual)}")
    for name in required:
        if struct.unpack(">II", (STORE / name).read_bytes()[16:24]) != SIZE:
            raise RuntimeError(f"Invalid screenshot dimensions: {name}")
    if not args.store_only:
        write_gallery_index(list(outputs))
    print(f"Generated {0 if args.store_only else len(outputs)} gallery variants and eight curated store images")


if __name__ == "__main__":
    main()
