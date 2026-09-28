#!/usr/bin/env python3
"""Create a deterministic, privacy-safe performance fixture from Kite presentation data."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
BASE_TIMESTAMP_MS = 1_767_225_600_000  # 2026-01-01T00:00:00Z
SAFE_ENUM_KEYS = {
    "algorithm",
    "format",
    "guest_access",
    "join_rule",
    "membership",
    "msgtype",
    "rel_type",
}
PRIVATE_TEXT_KEYS = {
    "avatar_url",
    "avatarUrl",
    "body",
    "displayName",
    "displayname",
    "eventId",
    "event_id",
    "external_url",
    "filename",
    "formatted_body",
    "lastEventId",
    "name",
    "roomId",
    "room_id",
    "senderAvatarUrl",
    "senderDisplayName",
    "senderId",
    "topic",
    "url",
}
SAFE_MSGTYPES = {
    "m.audio",
    "m.emote",
    "m.file",
    "m.image",
    "m.notice",
    "m.text",
    "m.video",
}
SAFE_MEMBERSHIPS = {"ban", "invite", "join", "knock", "leave"}
SAFE_FORMATS = {"org.matrix.custom.html"}
SAFE_ALGORITHMS = {"m.megolm.v1.aes-sha2"}
SAFE_JOIN_RULES = {"invite", "knock", "public", "restricted"}
SAFE_GUEST_ACCESS = {"can_join", "forbidden"}


class Anonymizer:
    def __init__(self) -> None:
        self.room_ids: dict[str, str] = {}
        self.user_ids: dict[str, str] = {}
        self.event_ids: dict[str, str] = {}
        self.media_ids: dict[str, str] = {}
        self.generic_ids: dict[str, str] = {}
        self._event_counter = 0

    def room_id(self, value: str) -> str:
        if value not in self.room_ids:
            self.room_ids[value] = f"!room{len(self.room_ids) + 1:04d}:perf.invalid"
        return self.room_ids[value]

    def user_id(self, value: str) -> str:
        if value not in self.user_ids:
            self.user_ids[value] = f"@user{len(self.user_ids) + 1:04d}:perf.invalid"
        return self.user_ids[value]

    def event_id(self, value: str) -> str:
        if value not in self.event_ids:
            self.event_ids[value] = f"$event{len(self.event_ids) + 1:06d}"
        return self.event_ids[value]

    def media_id(self, value: str) -> str:
        if value not in self.media_ids:
            self.media_ids[value] = f"fixture://media/{len(self.media_ids) + 1:05d}"
        return self.media_ids[value]

    def generic_id(self, value: str, prefix: str = "id") -> str:
        key = f"{prefix}:{value}"
        if key not in self.generic_ids:
            self.generic_ids[key] = f"{prefix}-{len(self.generic_ids) + 1:05d}"
        return self.generic_ids[key]

    @staticmethod
    def synthetic_text(value: str, label: str = "message") -> str:
        del label
        if not value:
            return ""
        digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
        alphabet = "qzxvkjwpfygb"
        out: list[str] = []
        cursor = 0
        for char in value[:4096]:
            if char.isspace():
                out.append(char)
                continue
            out.append(alphabet[int(digest[cursor % len(digest)], 16) % len(alphabet)])
            cursor += 1
        return "".join(out)

    @staticmethod
    def canonical_mimetype(value: str) -> str:
        major = value.split("/", 1)[0].lower()
        return {
            "audio": "audio/ogg",
            "image": "image/png",
            "video": "video/mp4",
            "text": "text/plain",
        }.get(major, "application/octet-stream")

    def sanitize_string(self, key: str | None, value: str) -> str:
        lower_key = (key or "").lower()

        if key == "msgtype":
            return value if value in SAFE_MSGTYPES else "m.text"
        if key == "membership":
            return value if value in SAFE_MEMBERSHIPS else "join"
        if key == "format":
            return value if value in SAFE_FORMATS else "org.matrix.custom.html"
        if key == "algorithm":
            return value if value in SAFE_ALGORITHMS else "m.megolm.v1.aes-sha2"
        if key == "join_rule":
            return value if value in SAFE_JOIN_RULES else "invite"
        if key == "guest_access":
            return value if value in SAFE_GUEST_ACCESS else "forbidden"
        if key == "mimetype":
            return self.canonical_mimetype(value)
        if key == "rel_type":
            return value if value.startswith("m.") else "m.reference"
        if key in {"event_id", "eventId", "lastEventId", "redacts"}:
            return self.event_id(value)
        if key in {"room_id", "roomId"} or lower_key.endswith("room_id"):
            return self.room_id(value)
        if key in {"senderId", "user_id", "userId"} or lower_key.endswith("user_id"):
            return self.user_id(value)
        if "avatar" in lower_key or "url" in lower_key or value.startswith(("mxc://", "http://", "https://")):
            return self.media_id(value)
        if lower_key in {"displayname", "display_name", "senderdisplayname"}:
            return f"User {len(self.user_ids) + 1:04d}"
        if key == "formatted_body":
            plain = re.sub(r"<[^>]+>", " ", value)
            return f"<p>{self.synthetic_text(plain, 'formatted')}</p>"
        if key in {"body", "filename", "name", "topic", "reason", "key"}:
            label = "file" if key == "filename" else "message"
            return self.synthetic_text(value, label)
        if lower_key.endswith("_id") or lower_key.endswith("id"):
            return self.generic_id(value, re.sub(r"[^a-z0-9]+", "-", lower_key).strip("-") or "id")
        if key in SAFE_ENUM_KEYS:
            return value
        return self.synthetic_text(value, "value")

    def sanitize_map_key(self, key: str, parent_key: str | None) -> str:
        if key.startswith("@") or parent_key == "users":
            return self.user_id(key)
        if key.startswith("!"):
            return self.room_id(key)
        if key.startswith("$"):
            return self.event_id(key)
        if key.startswith(("mxc://", "http://", "https://")):
            return self.media_id(key)
        if parent_key == "ciphertext":
            return self.generic_id(key, "ciphertext-key")
        return key

    def sanitize_value(self, value: Any, key: str | None = None) -> Any:
        if isinstance(value, dict):
            return {
                self.sanitize_map_key(str(k), key): self.sanitize_value(v, str(k))
                for k, v in value.items()
            }
        if isinstance(value, list):
            return [self.sanitize_value(item, key) for item in value]
        if isinstance(value, str):
            return self.sanitize_string(key, value)
        return value

    def room(self, source: dict[str, Any], index: int) -> dict[str, Any]:
        source_id = str(source.get("roomId", f"source-room-{index}"))
        room_id = self.room_id(source_id)
        return {
            "roomId": room_id,
            "displayName": self.synthetic_text(str(source.get("displayName") or f"room-{index + 1:03d}")),
            "avatarUrl": (
                f"fixture://avatar/room/{index + 1:03d}"
                if source.get("avatarUrl")
                else None
            ),
            "hasActiveCall": bool(source.get("hasActiveCall")),
            "highlightCount": int(source.get("highlightCount") or 0),
            "isDirect": bool(source.get("isDirect")),
            "isFavourite": bool(source.get("isFavourite")),
            "isMuted": bool(source.get("isMuted")),
            "lastActivityMs": BASE_TIMESTAMP_MS - (index * 60_000),
            "lastEventId": (
                self.event_id(str(source["lastEventId"]))
                if source.get("lastEventId")
                else None
            ),
            "streamPosition": index + 1,
            "unreadCount": int(source.get("unreadCount") or 0),
        }

    def event(self, source: dict[str, Any], index: int) -> dict[str, Any]:
        self._event_counter += 1
        source_sender = str(source.get("senderId", f"source-user-{index}"))
        sender_id = self.user_id(source_sender)
        event_id = self.event_id(str(source.get("eventId", f"source-event-{self._event_counter}")))
        source_room = str(source.get("roomId", "source-room-unknown"))
        return {
            "content": self.sanitize_value(source.get("content") or {}),
            "eventId": event_id,
            "originServerTimestampMs": BASE_TIMESTAMP_MS + (self._event_counter * 30_000),
            "roomId": self.room_id(source_room),
            "senderAvatarUrl": (
                f"fixture://avatar/user/{sender_id.split(':', 1)[0].lstrip('@')}"
                if source.get("senderAvatarUrl")
                else None
            ),
            "senderDisplayName": self.synthetic_text(str(source.get("senderDisplayName") or sender_id)),
            "senderId": sender_id,
            "streamPosition": self._event_counter,
            "type": str(source.get("type") or "m.room.message"),
        }


def collect_sensitive_strings(data: Any) -> set[str]:
    sensitive: set[str] = set()

    def visit(value: Any, key: str | None = None) -> None:
        if isinstance(value, dict):
            for child_key, child_value in value.items():
                visit(child_value, child_key)
        elif isinstance(value, list):
            for child in value:
                visit(child, key)
        elif isinstance(value, str) and key in PRIVATE_TEXT_KEYS and len(value) >= 6:
            sensitive.add(value)

    visit(data)
    return sensitive


def build_fixture(source: dict[str, Any]) -> dict[str, Any]:
    anonymizer = Anonymizer()
    rooms = [
        anonymizer.room(room, index)
        for index, room in enumerate(source.get("rooms") or [])
        if isinstance(room, dict)
    ]
    timelines: dict[str, list[dict[str, Any]]] = {}
    for source_room_id, events in (source.get("timelines") or {}).items():
        if not isinstance(events, list):
            continue
        room_id = anonymizer.room_id(str(source_room_id))
        timelines[room_id] = [
            anonymizer.event(event, index)
            for index, event in enumerate(events)
            if isinstance(event, dict)
        ]

    event_types = Counter(
        event["type"] for events in timelines.values() for event in events
    )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "description": (
            "An anonymized structural snapshot derived from a real Kite account. "
            "All names, identifiers, message bodies, timestamps, URLs and media references "
            "are deterministic synthetic values."
        ),
        "sourceStats": {
            "roomCount": len(rooms),
            "timelineCount": len(timelines),
            "eventCount": sum(len(events) for events in timelines.values()),
            "eventTypes": dict(sorted(event_types.items())),
        },
        "rooms": rooms,
        "timelines": timelines,
    }


def validate_no_sensitive_leak(source: dict[str, Any], fixture: dict[str, Any]) -> None:
    output_values: list[str] = []

    def collect_output_values(value: Any) -> None:
        if isinstance(value, dict):
            for child in value.values():
                collect_output_values(child)
        elif isinstance(value, list):
            for child in value:
                collect_output_values(child)
        elif isinstance(value, str):
            output_values.append(value)

    collect_output_values(fixture)
    leaked = [
        value
        for value in collect_sensitive_strings(source)
        if any(value in output_value for output_value in output_values)
    ]
    if leaked:
        raise RuntimeError(
            f"privacy validation failed: {len(leaked)} source values survived anonymization"
        )

    serialized = json.dumps(fixture, ensure_ascii=False)
    source_ids: set[str] = set()
    source_domains: set[str] = set()

    def collect_source_ids(value: Any, key: str | None = None) -> None:
        if isinstance(value, dict):
            for child_key, child_value in value.items():
                collect_source_ids(child_value, child_key)
        elif isinstance(value, list):
            for child in value:
                collect_source_ids(child, key)
        elif isinstance(value, str) and key in {
            "roomId",
            "room_id",
            "senderId",
            "user_id",
            "eventId",
            "event_id",
            "lastEventId",
        }:
            source_ids.add(value)
            if ":" in value and value[:1] in {"@", "!"}:
                source_domains.add(value.rsplit(":", 1)[1])

    collect_source_ids(source)
    if any(source_id in serialized for source_id in source_ids):
        raise RuntimeError("privacy validation failed: a source Matrix identifier survived")
    if any(domain in serialized for domain in source_domains):
        raise RuntimeError("privacy validation failed: a source Matrix server name survived")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    source = json.loads(args.input.read_text(encoding="utf-8"))
    fixture = build_fixture(source)
    validate_no_sensitive_leak(source, fixture)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(fixture, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    stats = fixture["sourceStats"]
    print(
        "wrote anonymized fixture: "
        f"{stats['roomCount']} rooms, {stats['timelineCount']} timelines, "
        f"{stats['eventCount']} events"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
