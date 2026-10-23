#!/usr/bin/env python3
"""Seed an isolated Synapse with fictional Kite conversations for device captures."""

import argparse
import hashlib
import hmac
import json
from pathlib import Path
import subprocess
import tempfile
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen


PEOPLE = ["taylor", "alex", "maya", "sam", "jordan", "priya", "chris", "noa", "river"]
NAMES = ["Taylor", "Alex", "Maya", "Sam", "Jordan", "Priya", "Chris", "Noa", "River"]
AVATAR_COLORS = [
    "#7A63BC", "#CF7598", "#4F91A4", "#E4A055", "#687FC2",
    "#8AAB72", "#BA7BB8", "#C47765", "#5FA8A0",
]


def request(base, route, token=None, payload=None, method=None, content_type="application/json"):
    data = None if payload is None else (
        json.dumps(payload).encode() if content_type == "application/json" else payload
    )
    headers = {"Content-Type": content_type}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = Request(base + route, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except HTTPError as error:
        raise RuntimeError(f"{route}: HTTP {error.code} {error.read()[:300]!r}") from error


def register(base, username, password, secret):
    nonce = request(base, "/_synapse/admin/v1/register")["nonce"]
    digest = hmac.new(secret.encode(), digestmod=hashlib.sha1)
    digest.update(f"{nonce}\0{username}\0{password}\0notadmin".encode())
    return request(base, "/_synapse/admin/v1/register", payload={
        "nonce": nonce, "username": username, "password": password,
        "admin": False, "mac": digest.hexdigest(),
    })


def send(base, token, room, txn, body, msgtype="m.text", **extras):
    route = f"/_matrix/client/v3/rooms/{quote(room, safe='')}/send/m.room.message/{txn}"
    return request(base, route, token, {"body": body, "msgtype": msgtype, **extras}, "PUT")["event_id"]


def upload_landscape(base, token):
    with tempfile.TemporaryDirectory(prefix="kite-fixture-media-") as directory:
        png = Path(directory) / "sunset.png"
        subprocess.run([
            "rsvg-convert", "-f", "png", "-o", str(png),
            str(Path(__file__).resolve().parents[1] / "screenshots/fixture-landscape.svg"),
        ], check=True)
        data = png.read_bytes()
    uri = request(
        base, "/_matrix/media/v3/upload?filename=sunset.png",
        token, data, "POST", "image/png",
    )["content_uri"]
    return uri, len(data)


def set_avatar(base, server, token, user, name, color):
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256">
      <rect width="256" height="256" rx="128" fill="{color}"/>
      <circle cx="64" cy="46" r="115" fill="#fff" opacity=".11"/>
      <text x="128" y="162" text-anchor="middle" font-size="118"
        font-family="DejaVu Sans" font-weight="bold" fill="white">{name[0]}</text>
      </svg>'''
    png = subprocess.run(["rsvg-convert", "-f", "png"],
                         input=svg.encode(), capture_output=True, check=True).stdout
    uri = request(base, f"/_matrix/media/v3/upload?filename={user}.png",
                  token, png, "POST", "image/png")["content_uri"]
    request(base, f"/_matrix/client/v3/profile/@{user}:{server}/avatar_url",
            token, {"avatar_url": uri}, "PUT")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://192.168.240.1:18887")
    parser.add_argument("--server-name", default="kite-screenshots.test")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    import re
    config = args.config.read_text()
    secret = re.search(r'^registration_shared_secret: "([^"]+)"', config, re.M).group(1)
    password = "Only-For-Isolated-Kite-Screenshots-2026!"
    tokens = {}
    for user, name, color in zip(PEOPLE, NAMES, AVATAR_COLORS):
        try:
            tokens[user] = register(args.url, user, password, secret)["access_token"]
        except RuntimeError as error:
            if "M_USER_IN_USE" not in str(error):
                raise
            tokens[user] = request(args.url, "/_matrix/client/v3/login", payload={
                "type": "m.login.password",
                "identifier": {"type": "m.id.user", "user": user},
                "password": password,
            })["access_token"]
        request(args.url, f"/_matrix/client/v3/profile/@{user}:{args.server_name}/displayname",
                tokens[user], {"displayname": name}, "PUT")
        set_avatar(args.url, args.server_name, tokens[user], user, name, color)

    count = 0
    rooms = {}
    directs = {}

    def create(key, label, members, direct=False):
        participants = members if not direct else [members[0]]
        # Creation+join is performed through the real Matrix Client-Server API.
        r = request(args.url, "/_matrix/client/v3/createRoom", tokens["taylor"], {
            "name": label, "preset": "private_chat",
            "is_direct": direct,
            "invite": [f"@{name}:{args.server_name}" for name in participants],
        })["room_id"]
        for name in participants:
            request(args.url, f"/_matrix/client/v3/join/{quote(r, safe='')}",
                    tokens[name], {}, "POST")
        rooms[key] = r
        if direct:
            directs[f"@{members[0]}:{args.server_name}"] = [r]
        return r

    def chat(room, who, body, **extras):
        nonlocal count
        count += 1
        return send(args.url, tokens[who], room, f"fixture-{count}", body, **extras)

    designs = create("design", "Design Crew", ["maya", "jordan", "priya", "chris", "noa"])
    chat(designs, "maya", "Morning everyone! How's the prototype looking?")
    chat(designs, "jordan", "The new navigation feels brilliant ✨")
    chat(designs, "taylor", "Nice. Let's look at the final details before Friday.")
    chat(designs, "priya", "I've added a few notes to the design thread.")
    chat(designs, "maya", "Perfect — can everyone review the screens today?")
    group_anchor = chat(designs, "taylor", "Absolutely, on it! 🚀")

    planning = create("planning", "Friday Plans", ["sam", "alex", "river"])
    chat(planning, "sam", "Got us a table for 7:30 🍕")
    chat(planning, "river", "Amazing. I'll bring the board game.")
    chat(planning, "taylor", "Can't wait 😂")
    chat(planning, "alex", "See you all there!")

    maya = create("maya", "Maya", ["maya"], True)
    chat(maya, "maya", "Did you see the photos from the hike?")
    chat(maya, "taylor", "Those views were unreal 😍")
    chat(maya, "maya", "We should go again next weekend.")
    uri, size = upload_landscape(args.url, tokens["maya"])
    chat(maya, "maya", "Sunset at the lake", msgtype="m.image", url=uri, info={
        "mimetype": "image/png", "w": 1200, "h": 900, "size": size,
    })

    jordan = create("jordan", "Jordan", ["jordan"], True)
    chat(jordan, "jordan", "I finished the mockups!")
    chat(jordan, "taylor", "Awesome, sending feedback now.")

    sam = create("sam", "Sam", ["sam"], True)
    chat(sam, "sam", "Coffee tomorrow?")
    chat(sam, "taylor", "Yes! Same place, 10-ish?")
    chat(sam, "sam", "Perfect ☕")

    alex = create("alex", "Alex", ["alex"], True)
    chat(alex, "alex", "Hey! How's your day going?")
    chat(alex, "taylor", "Pretty good! Just wrapped up a big project.")
    chat(alex, "alex", "Nice! We should celebrate 🎉")
    chat(alex, "taylor", "Absolutely. Dinner this weekend?")
    chat(alex, "alex", "That sounds great. Saturday?")
    reaction_target = chat(alex, "taylor", "Saturday works! ❤️")
    chat(alex, "alex", "Perfect, I'll book somewhere fun!")
    request(args.url, f"/_matrix/client/v3/rooms/{quote(alex, safe='')}/send/m.reaction/react-{count}",
            tokens["alex"], {"m.relates_to": {
                "rel_type": "m.annotation", "event_id": reaction_target, "key": "❤️",
            }}, "PUT")
    chat(alex, "taylor", "You always pick the best spots 😊")

    # Account data marks these genuine private rooms as DMs in Kite's inbox.
    request(args.url, f"/_matrix/client/v3/user/@taylor:{args.server_name}/account_data/m.direct",
            tokens["taylor"], directs, "PUT")
    request(args.url, f"/_matrix/client/v3/user/@taylor:{args.server_name}/rooms/{quote(designs, safe='')}/tags/m.favourite",
            tokens["taylor"], {"order": 0.1}, "PUT")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "url": args.url, "server_name": args.server_name,
        "username": "taylor", "password": password,
        "tokens": tokens, "rooms": rooms, "reaction_target": reaction_target,
        "group_anchor": group_anchor,
    }, indent=2))
    args.output.chmod(0o600)
    print(f"Seeded {len(PEOPLE)} fictional users, {len(rooms)} rooms, {count} messages")


if __name__ == "__main__":
    main()
