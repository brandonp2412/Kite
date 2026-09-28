#!/usr/bin/env python3
"""Seed a local Synapse with the anonymized Kite performance fixture."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import struct
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from pathlib import Path
from typing import Any

SEED_VERSION = 1
DEFAULT_PASSWORD = "kite-perf-local-only"


def json_bytes(value: Any) -> bytes:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


class MatrixApi:
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.transaction = 0

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def request(
        self,
        method: str,
        path: str,
        *,
        body: Any | None = None,
        token: str | None = None,
        raw_body: bytes | None = None,
        content_type: str = "application/json",
        expected: set[int] | None = None,
    ) -> tuple[int, Any]:
        headers = {"Content-Type": content_type}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        data = raw_body if raw_body is not None else (json_bytes(body) if body is not None else None)
        request = urllib.request.Request(
            self._url(path),
            method=method,
            data=data,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
                status = response.status
        except urllib.error.HTTPError as error:
            payload = error.read()
            status = error.code

        accepted = expected or set(range(200, 300))
        if status not in accepted:
            detail = payload.decode("utf-8", errors="replace")[:1000]
            raise RuntimeError(f"{method} {path} failed with HTTP {status}: {detail}")

        if not payload:
            return status, {}
        if content_type == "application/json" or payload[:1] in {b"{", b"["}:
            try:
                return status, json.loads(payload)
            except json.JSONDecodeError:
                pass
        return status, payload

    def login(self, user: str, password: str) -> tuple[str, str]:
        _, response = self.request(
            "POST",
            "/_matrix/client/v3/login",
            body={
                "type": "m.login.password",
                "identifier": {"type": "m.id.user", "user": user},
                "password": password,
            },
        )
        return str(response["access_token"]), str(response["user_id"])

    def create_user(
        self,
        admin_token: str,
        user_id: str,
        password: str,
        display_name: str,
    ) -> None:
        quoted = urllib.parse.quote(user_id, safe="")
        self.request(
            "PUT",
            f"/_synapse/admin/v2/users/{quoted}",
            token=admin_token,
            body={
                "password": password,
                "displayname": display_name,
                "admin": False,
                "deactivated": False,
            },
            expected={200, 201},
        )

    def upload(
        self,
        token: str,
        data: bytes,
        *,
        filename: str,
        content_type: str,
    ) -> str:
        query = urllib.parse.urlencode({"filename": filename})
        _, response = self.request(
            "POST",
            f"/_matrix/media/v3/upload?{query}",
            token=token,
            raw_body=data,
            content_type=content_type,
        )
        return str(response["content_uri"])

    def set_profile(
        self,
        token: str,
        user_id: str,
        *,
        display_name: str,
        avatar_url: str,
    ) -> None:
        quoted = urllib.parse.quote(user_id, safe="")
        self.request(
            "PUT",
            f"/_matrix/client/v3/profile/{quoted}/displayname",
            token=token,
            body={"displayname": display_name},
        )
        self.request(
            "PUT",
            f"/_matrix/client/v3/profile/{quoted}/avatar_url",
            token=token,
            body={"avatar_url": avatar_url},
        )

    def create_room(
        self,
        token: str,
        *,
        name: str,
        avatar_url: str | None,
        topic: str,
    ) -> str:
        initial_state: list[dict[str, Any]] = []
        if avatar_url:
            initial_state.append(
                {"type": "m.room.avatar", "state_key": "", "content": {"url": avatar_url}}
            )
        if topic:
            initial_state.append(
                {"type": "m.room.topic", "state_key": "", "content": {"topic": topic}}
            )
        _, response = self.request(
            "POST",
            "/_matrix/client/v3/createRoom",
            token=token,
            body={
                "preset": "private_chat",
                "name": name,
                "initial_state": initial_state,
            },
        )
        return str(response["room_id"])

    def invite(self, token: str, room_id: str, user_id: str) -> None:
        room = urllib.parse.quote(room_id, safe="")
        self.request(
            "POST",
            f"/_matrix/client/v3/rooms/{room}/invite",
            token=token,
            body={"user_id": user_id},
        )

    def join(self, token: str, room_id: str) -> None:
        room = urllib.parse.quote(room_id, safe="")
        self.request(
            "POST",
            f"/_matrix/client/v3/join/{room}",
            token=token,
            body={},
        )

    def send(self, token: str, room_id: str, event_type: str, content: dict[str, Any]) -> str:
        self.transaction += 1
        room = urllib.parse.quote(room_id, safe="")
        event = urllib.parse.quote(event_type, safe="")
        _, response = self.request(
            "PUT",
            f"/_matrix/client/v3/rooms/{room}/send/{event}/perf-{self.transaction:08d}",
            token=token,
            body=content,
        )
        return str(response["event_id"])

    def put_account_data(
        self,
        token: str,
        user_id: str,
        event_type: str,
        content: dict[str, Any],
    ) -> None:
        user = urllib.parse.quote(user_id, safe="")
        event = urllib.parse.quote(event_type, safe="")
        self.request(
            "PUT",
            f"/_matrix/client/v3/user/{user}/account_data/{event}",
            token=token,
            body=content,
        )

    def favourite_room(self, token: str, user_id: str, room_id: str) -> None:
        user = urllib.parse.quote(user_id, safe="")
        room = urllib.parse.quote(room_id, safe="")
        self.request(
            "PUT",
            f"/_matrix/client/v3/user/{user}/rooms/{room}/tags/m.favourite",
            token=token,
            body={"order": 0.5},
        )

    def mute_room(self, token: str, room_id: str) -> None:
        rule = urllib.parse.quote(room_id, safe="")
        self.request(
            "PUT",
            f"/_matrix/client/v3/pushrules/global/room/{rule}",
            token=token,
            body={"actions": ["dont_notify"]},
        )


def png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + chunk_type
        + payload
        + struct.pack(">I", binascii.crc32(chunk_type + payload) & 0xFFFFFFFF)
    )


def synthetic_png(width: int, height: int, seed: str) -> bytes:
    width = max(16, min(width, 1280))
    height = max(16, min(height, 1280))
    digest = hashlib.sha256(seed.encode("utf-8")).digest()
    rgb_a = digest[0:3]
    rgb_b = digest[3:6]
    rows: list[bytes] = []
    for y in range(height):
        color = rgb_a if (y // 24) % 2 == 0 else rgb_b
        rows.append(b"\x00" + color * width)
    payload = zlib.compress(b"".join(rows), level=6)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + png_chunk(b"IDAT", payload)
        + png_chunk(b"IEND", b"")
    )


def fixture_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def numeric(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def relation_rewrite(value: Any, event_ids: dict[str, str]) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, child in value.items():
            if key == "event_id" and isinstance(child, str):
                result[key] = event_ids.get(child, child)
            else:
                result[key] = relation_rewrite(child, event_ids)
        return result
    if isinstance(value, list):
        return [relation_rewrite(child, event_ids) for child in value]
    return value


def make_message_content(
    api: MatrixApi,
    token: str,
    event: dict[str, Any],
    server_event_ids: dict[str, str],
) -> dict[str, Any]:
    source = event.get("content") if isinstance(event.get("content"), dict) else {}
    msgtype = str(source.get("msgtype") or "m.text")
    body = str(source.get("body") or "qzxv kjwp fygb")

    if msgtype == "m.image":
        info = source.get("info") if isinstance(source.get("info"), dict) else {}
        width = numeric(info.get("w"), 720)
        height = numeric(info.get("h"), 720)
        image = synthetic_png(width, height, str(event.get("eventId")))
        url = api.upload(
            token,
            image,
            filename=f"fixture-{api.transaction:05d}.png",
            content_type="image/png",
        )
        return {
            "msgtype": "m.image",
            "body": body,
            "url": url,
            "info": {
                "mimetype": "image/png",
                "size": len(image),
                "w": max(16, min(width, 1280)),
                "h": max(16, min(height, 1280)),
            },
        }

    if msgtype in {"m.audio", "m.file", "m.video"}:
        return {
            "msgtype": "m.file",
            "body": body,
            "filename": str(source.get("filename") or "qzxv-file.bin"),
        }

    content: dict[str, Any] = {"msgtype": msgtype if msgtype in {"m.text", "m.notice", "m.emote"} else "m.text", "body": body}
    if source.get("format") == "org.matrix.custom.html" and source.get("formatted_body"):
        content["format"] = "org.matrix.custom.html"
        content["formatted_body"] = str(source["formatted_body"])
    relates_to = source.get("m.relates_to")
    if isinstance(relates_to, dict):
        content["m.relates_to"] = relation_rewrite(relates_to, server_event_ids)
    return content


def seed(
    *,
    api: MatrixApi,
    fixture_path: Path,
    marker_path: Path,
    server_name: str,
    admin_user: str,
    password: str,
    sender_count: int,
) -> None:
    fixture_hash = fixture_sha256(fixture_path)
    if marker_path.exists():
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        if marker.get("fixtureSha256") == fixture_hash and marker.get("seedVersion") == SEED_VERSION:
            api.login(admin_user, password)
            print("fixture already seeded; reusing persistent Synapse data")
            return
        raise RuntimeError("existing Synapse seed does not match the fixture; reset the perf state directory")

    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    rooms = list(fixture.get("rooms") or [])
    timelines = dict(fixture.get("timelines") or {})

    admin_token, admin_user_id = api.login(admin_user, password)

    sender_tokens: list[tuple[str, str]] = []
    for index in range(sender_count):
        localpart = f"perf-user-{index + 1:02d}"
        user_id = f"@{localpart}:{server_name}"
        display_name = f"Fixture User {index + 1:02d}"
        api.create_user(admin_token, user_id, password, display_name)
        token, actual_user_id = api.login(localpart, password)
        avatar = synthetic_png(96, 96, f"user-avatar-{index}")
        avatar_url = api.upload(
            token,
            avatar,
            filename=f"user-{index + 1:02d}.png",
            content_type="image/png",
        )
        api.set_profile(
            token,
            actual_user_id,
            display_name=display_name,
            avatar_url=avatar_url,
        )
        sender_tokens.append((actual_user_id, token))

    room_map: dict[str, str] = {}
    direct_rooms: dict[str, list[str]] = {}
    timeline_room_ids = set(timelines)

    print(f"creating {len(rooms)} rooms")
    for index, room in enumerate(rooms):
        fixture_room_id = str(room["roomId"])
        avatar_url: str | None = None
        if room.get("avatarUrl"):
            avatar = synthetic_png(96, 96, f"room-avatar-{index}")
            avatar_url = api.upload(
                admin_token,
                avatar,
                filename=f"room-{index + 1:03d}.png",
                content_type="image/png",
            )
        server_room_id = api.create_room(
            admin_token,
            name=str(room.get("displayName") or f"Fixture {index + 1:03d}"),
            avatar_url=avatar_url,
            topic="qzxv kjwp fygb",
        )
        room_map[fixture_room_id] = server_room_id

        if room.get("isFavourite"):
            api.favourite_room(admin_token, admin_user_id, server_room_id)
        if room.get("isMuted"):
            api.mute_room(admin_token, server_room_id)

        if fixture_room_id in timeline_room_ids:
            for sender_user_id, sender_token in sender_tokens:
                api.invite(admin_token, server_room_id, sender_user_id)
                api.join(sender_token, server_room_id)

        if room.get("isDirect") and sender_tokens:
            direct_rooms.setdefault(sender_tokens[0][0], []).append(server_room_id)

        if (index + 1) % 25 == 0:
            print(f"  rooms: {index + 1}/{len(rooms)}")

    if direct_rooms:
        api.put_account_data(admin_token, admin_user_id, "m.direct", direct_rooms)

    event_id_map: dict[str, str] = {}
    ordered_timelines = sorted(
        timelines.items(),
        key=lambda item: len(item[1]) if isinstance(item[1], list) else 0,
    )
    total_events = sum(len(events) for _, events in ordered_timelines if isinstance(events, list))
    seeded_events = 0
    print(f"seeding {total_events} timeline events")

    for fixture_room_id, events in ordered_timelines:
        if not isinstance(events, list) or fixture_room_id not in room_map:
            continue
        server_room_id = room_map[fixture_room_id]
        for event in events:
            if not isinstance(event, dict):
                continue
            event_type = str(event.get("type") or "")
            sender_key = str(event.get("senderId") or "")
            sender_index = int(hashlib.sha256(sender_key.encode("utf-8")).hexdigest()[:8], 16) % (len(sender_tokens) + 1)
            if sender_index == len(sender_tokens):
                token = admin_token
            else:
                token = sender_tokens[sender_index][1]

            fixture_event_id = str(event.get("eventId") or "")
            if event_type == "m.room.message":
                content = make_message_content(api, token, event, event_id_map)
                server_event_id = api.send(token, server_room_id, event_type, content)
                if fixture_event_id:
                    event_id_map[fixture_event_id] = server_event_id
            elif event_type == "m.reaction":
                content = event.get("content") if isinstance(event.get("content"), dict) else {}
                relation = content.get("m.relates_to") if isinstance(content.get("m.relates_to"), dict) else {}
                target = event_id_map.get(str(relation.get("event_id") or ""))
                if target:
                    server_event_id = api.send(
                        token,
                        server_room_id,
                        "m.reaction",
                        {
                            "m.relates_to": {
                                "rel_type": "m.annotation",
                                "event_id": target,
                                "key": f"👍{fixture_event_id[-6:]}",
                            }
                        },
                    )
                    if fixture_event_id:
                        event_id_map[fixture_event_id] = server_event_id

            seeded_events += 1
            if seeded_events % 100 == 0:
                print(f"  events: {seeded_events}/{total_events}")

    marker_path.parent.mkdir(parents=True, exist_ok=True)
    marker_path.write_text(
        json.dumps(
            {
                "seedVersion": SEED_VERSION,
                "fixtureSha256": fixture_hash,
                "roomCount": len(rooms),
                "timelineCount": len(timelines),
                "eventCount": total_events,
                "seededAtUnix": int(time.time()),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print("fixture seed complete")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--marker", type=Path, required=True)
    parser.add_argument("--base-url", default="http://127.0.0.1:8008")
    parser.add_argument("--server-name", default="kite-perf.test")
    parser.add_argument("--admin-user", default="perf")
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--sender-count", type=int, default=4)
    args = parser.parse_args()

    seed(
        api=MatrixApi(args.base_url),
        fixture_path=args.fixture,
        marker_path=args.marker,
        server_name=args.server_name,
        admin_user=args.admin_user,
        password=args.password,
        sender_count=max(1, args.sender_count),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
