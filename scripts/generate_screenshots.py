#!/usr/bin/env python3
"""Capture Kite itself on isolated Android/Matrix fixtures; never draw UI mockups."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
GALLERY = ROOT / "screenshots/generated/native"
STORE = ROOT / "metadata/en-US/images/phoneScreenshots"
DEVICE_FILTER = "/home/brandon/.local/bin/mobile-mcp-device-filter"
FIXTURE_USER = "@taylor:kite-screenshots.test"

# Play listing: exactly eight genuine device captures, ordered by impact.
CURATED = [
    "light-inbox", "light-chat-direct", "dark-chat-reactions",
    "light-chat-group", "light-chat-media", "light-search-rooms",
    "light-settings", "dark-chat-attachment-picker",
]


class Android:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *args, timeout=30, binary=False):
        result = subprocess.run(
            ["adb", "-s", self.serial, *args],
            capture_output=True, timeout=timeout, check=True,
            text=not binary,
        )
        return result.stdout

    def shell(self, *args):
        return self.adb("shell", *args)

    def nodes(self):
        result = subprocess.run(
            [DEVICE_FILTER, "dump", "ui", "--device", self.serial],
            capture_output=True, text=True, check=True, timeout=30,
        )
        def flatten(values):
            for node in values:
                yield node
                yield from flatten(node.get("children", []))
        return list(flatten(json.loads(result.stdout)["data"]["elements"]))

    def find(self, value, field="text", contains=False):
        for node in reversed(self.nodes()):
            candidate = node.get(field, "")
            if (value in candidate if contains else candidate == value):
                return node
        raise LookupError(f"No Android {field} matching {value!r}")

    def wait(self, value, field="text", timeout=25):
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            try:
                return self.find(value, field)
            except (LookupError, subprocess.SubprocessError, KeyError, ValueError):
                time.sleep(0.6)
        raise TimeoutError(f"Android never displayed {value!r}")

    def tap(self, x, y):
        self.shell("input", "tap", str(int(x)), str(int(y)))
        time.sleep(0.35)

    def tap_node(self, value, field="text"):
        bounds = self.wait(value, field)["rect"]
        self.tap(bounds["x"] + bounds["width"] // 2,
                 bounds["y"] + bounds["height"] // 2)

    def hold(self, value, field="text"):
        b = self.wait(value, field)["rect"]
        x, y = b["x"] + b["width"] // 2, b["y"] + b["height"] // 2
        self.shell("input", "swipe", str(x), str(y), str(x), str(y), "700")
        time.sleep(0.6)

    def back(self):
        self.shell("input", "keyevent", "4")
        time.sleep(0.3)

    def type(self, value):
        assert re.fullmatch("[a-zA-Z0-9_-]+", value), "Search fixture text only"
        self.shell("input", "text", value)
        time.sleep(0.7)

    def inbox(self):
        self.shell("am", "force-stop", "app.kite")
        self.shell("am", "start", "-n", "app.kite/chat.schildi.revenge.MainActivity")
        self.wait("Alex")
        self.wait("Search")

    def demo_status_bar(self):
        self.shell("settings", "put", "global", "sysui_demo_allowed", "1")
        for extras in [
            ["command", "enter"], ["command", "clock", "hhmm", "0941"],
            ["command", "notifications", "visible", "false"],
            ["command", "battery", "level", "100", "plugged", "false"],
        ]:
            pairs = [piece for i in range(0, len(extras), 2)
                     for piece in ("-e", extras[i], extras[i + 1])] if len(extras) % 2 == 0 else ["-e", "command", "enter"]
            self.shell("am", "broadcast", "-a", "com.android.systemui.demo", *pairs)

    def theme(self, name):
        self.shell("cmd", "uimode", "night", "yes" if name == "dark" else "no")
        time.sleep(1)
        self.demo_status_bar()

    def capture(self, name):
        # Genuine Android compositor capture, including system status/navigation.
        destination = GALLERY / f"{name}.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        time.sleep(0.7)
        data = self.adb("exec-out", "screencap", "-p", binary=True)
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise RuntimeError(f"{name}: not an Android PNG")
        w, h = struct.unpack(">II", data[16:24])
        if w < 720 or h < 1280 or len(data) < 15000:
            raise RuntimeError(f"{name}: suspicious capture ({w}x{h}, {len(data)} bytes)")
        destination.write_bytes(data)
        print(f"CAPTURE {name} {w}x{h}", flush=True)
        return {"name": name, "file": str(destination.relative_to(ROOT)),
                "width": w, "height": h, "sha256": hashlib.sha256(data).hexdigest()}


def perform_shots(device, theme):
    shots, failures = [], {}
    def shot(name, action):
        try:
            action()
            shots.append(device.capture(f"{theme}-{name}"))
        except Exception as error:
            failures[name] = str(error)
            print(f"SKIPPED {theme}-{name}: {error}", flush=True)

    device.theme(theme)
    shot("inbox", lambda: device.inbox())

    def accounts():
        device.inbox()
        device.tap(965, 2050)
        device.wait("Settings")
        device.tap_node("Accounts", "label")
        device.wait(FIXTURE_USER)
    shot("accounts", accounts)

    def settings():
        device.inbox()
        device.tap(965, 2050)
        device.wait("Settings")
        device.wait("General")
    shot("settings", settings)
    for key, title in [
        ("settings-general", "General"),
        ("settings-notifications", "Notifications"),
        ("settings-inbox", "Inbox"),
        ("settings-conversation", "Conversation screen"),
    ]:
        def section(title=title):
            settings()
            device.tap_node(title)
            device.wait(title)
        shot(key, section)

    def direct():
        device.inbox()
        device.tap_node("Alex")
        device.wait("Saturday works! ❤️")
    shot("chat-direct", direct)

    def reactions():
        direct()
        device.hold("Saturday works! ❤️")
        device.wait("React ❤️", "label")
        device.wait("Select")
    shot("chat-reactions", reactions)

    def selection():
        reactions()
        device.tap_node("Select")
        device.wait("1 selected")
    shot("chat-selection", selection)

    def emoji_picker():
        reactions()
        device.tap_node("React", "label")
        device.wait("Search emoji")
    shot("chat-emoji-picker", emoji_picker)

    def selection_actions():
        selection()
        device.tap_node("Show more", "label")
        device.wait("Message info")
    shot("chat-selection-actions", selection_actions)

    def reply_preview():
        selection()
        device.tap_node("Reply", "label")
        device.wait("Clear reply", "label")
    shot("chat-reply-preview", reply_preview)

    def chat_search():
        direct()
        device.tap_node("Search", "label")
        device.wait("Search")
    shot("chat-search", chat_search)

    def direct_details():
        direct()
        device.tap_node("Alex")
        device.wait("Room details")
    shot("chat-direct-details", direct_details)

    def draft():
        direct()
        device.tap(380, 2053)
        device.type("Weekend")
        device.back()
    shot("chat-composer", draft)

    def group():
        device.inbox()
        device.tap_node("Design Crew")
        device.wait("Absolutely, on it! 🚀")
    shot("chat-group", group)

    def group_reactions():
        group()
        device.hold("Absolutely, on it! 🚀")
        device.wait("React ❤️", "label")
    shot("chat-group-reactions", group_reactions)

    def details():
        group()
        device.tap_node("Design Crew")
        device.wait("Room details")
    shot("room-details", details)

    def members():
        details()
        device.tap_node("Room members", "label")
        device.wait("6 members")
    shot("room-members", members)

    def media():
        device.inbox()
        device.tap_node("Maya")
        device.wait("Maya")
        device.wait("Message")
        time.sleep(1.5)
    shot("chat-media", media)

    def picker():
        media()
        device.tap(113, 2053)  # The left +, not the gallery shortcut at right.
        device.wait("Open gallery", "label")
    shot("chat-attachment-picker", picker)

    def search(value):
        device.inbox()
        device.tap(300, 2050)
        device.type(value)
        device.back()
        device.wait(value)
    shot("search-rooms", lambda: search("design"))
    shot("search-empty", lambda: search("zznotfound"))

    def room_context():
        device.inbox()
        device.hold("Alex")
    shot("inbox-context", room_context)
    return shots, failures


def write_index(shots):
    cards = "".join(
        f'<a href="generated/native/{row["name"]}.png" data-name="{row["name"]}">'
        f'<img loading="lazy" src="generated/native/{row["name"]}.png">'
        f'<span>{row["name"].replace("-", " ")}{" ★" if row["name"] in CURATED else ""}</span></a>'
        for row in [*(x for name in CURATED for x in shots if x["name"] == name),
                    *(x for x in shots if x["name"] not in CURATED)]
    )
    (ROOT / "screenshots/index.html").write_text(
        '<!doctype html><html lang="en"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Kite real Android screenshots</title>'
        '<style>body{background:#17141d;color:white;font:16px system-ui;padding:30px}'
        'input{padding:14px;border-radius:12px}main{display:grid;grid-template-columns:'
        'repeat(auto-fill,minmax(230px,1fr));gap:20px;margin-top:24px}'
        'a{color:inherit;text-decoration:none;background:#292530;border-radius:18px;'
        'overflow:hidden}img{width:100%;display:block}span{display:block;padding:12px}'
        '</style><h1>Kite • genuine Android captures</h1>'
        '<p>Fictional Matrix accounts and messages. Store selections marked ★.</p>'
        '<input type="search" placeholder="Filter screenshots" oninput="for(let a of '
        'document.querySelectorAll(\'main a\'))a.hidden=!a.dataset.name.includes(this.value)">'
        f'<main>{cards}</main></html>'
    )


def promote(shots):
    by_name = {shot["name"]: shot for shot in shots}
    if not all(name in by_name for name in CURATED):
        raise RuntimeError("Missing genuine curated captures; existing Fastlane images preserved")
    if len({by_name[name]["sha256"] for name in CURATED}) != 8:
        raise RuntimeError("Duplicate curated screenshot; existing Fastlane images preserved")
    STORE.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(CURATED, 1):
        shutil.copy2(ROOT / by_name[name]["file"], STORE / f"{index}_en-US.png")
    for other in STORE.glob("*_en-US.png"):
        if other.stem.split("_")[0].isdigit() and other.name not in {
            f"{i}_en-US.png" for i in range(1, 9)
        }:
            other.unlink()
    print("PROMOTED eight native Android captures to Fastlane", flush=True)


def verify():
    manifest = json.loads((ROOT / "screenshots/native-manifest.json").read_text())
    assert manifest["source"] == "adb exec-out screencap -p"
    assert manifest["fixture_user"] == FIXTURE_USER
    screenshots = {row["name"]: row for row in manifest["screenshots"]}
    assert len(screenshots) == len(manifest["screenshots"])
    assert len(screenshots) >= 40
    assert not any(manifest["failures"].values())
    assert len(CURATED) == 8 and all(name in screenshots for name in CURATED)
    assert {p.name for p in STORE.glob("*_en-US.png")} == {
        f"{i}_en-US.png" for i in range(1, 9)
    }
    for name, shot in screenshots.items():
        data = (ROOT / shot["file"]).read_bytes()
        assert data.startswith(b"\x89PNG\r\n\x1a\n")
        assert struct.unpack(">II", data[16:24]) == (shot["width"], shot["height"])
        assert hashlib.sha256(data).hexdigest() == shot["sha256"]
    for index, name in enumerate(CURATED, 1):
        data = (ROOT / screenshots[name]["file"]).read_bytes()
        assert (STORE / f"{index}_en-US.png").read_bytes() == data
    print(f"Verified {len(screenshots)} native Android captures and eight Fastlane images")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="192.168.240.112:5555")
    parser.add_argument("--theme", choices=["both", "light", "dark"], default="both")
    parser.add_argument("--curate-only", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        verify()
        return
    if args.curate_only:
        manifest = json.loads((ROOT / "screenshots/native-manifest.json").read_text())
        promote(manifest["screenshots"])
        return
    device = Android(args.device)
    if "app.kite" not in device.shell("pm", "list", "packages", "app.kite"):
        raise RuntimeError("Install Kite on the isolated Android device first")
    device.inbox()
    device.tap(965, 2050)
    device.wait("Settings")
    device.tap_node("Accounts", "label")
    device.wait(FIXTURE_USER)  # Never capture a real Matrix account.
    all_shots, all_failures = [], {}
    for theme in (["light", "dark"] if args.theme == "both" else [args.theme]):
        shots, failures = perform_shots(device, theme)
        all_shots += shots
        all_failures[theme] = failures
    manifest = {"source": "adb exec-out screencap -p", "device": args.device,
                "fixture_user": FIXTURE_USER, "screenshots": all_shots,
                "failures": all_failures, "curated": CURATED}
    (ROOT / "screenshots/native-manifest.json").write_text(json.dumps(manifest, indent=2))
    write_index(all_shots)
    promote(all_shots)
    print(f"Captured {len(all_shots)} genuine Kite screenshots", flush=True)


if __name__ == "__main__":
    main()
