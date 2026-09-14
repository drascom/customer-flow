#!/usr/bin/env python3
"""Create missing thumbnails for media uploaded before thumbnail support."""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from app import ensure_thumbnail, thumbnail_path


BACKFILL_ID = "2026-09-photo-thumbnails-v2"


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def referenced_media(db_path: Path) -> list[tuple[str, str, str]]:
    with sqlite3.connect(db_path) as connection:
        photos = connection.execute(
            "SELECT 'photo',id,file_path FROM photos WHERE file_path IS NOT NULL"
        ).fetchall()
        messages = connection.execute(
            "SELECT 'message',id,attachment_path FROM messages WHERE attachment_path IS NOT NULL"
        ).fetchall()
    return [(str(kind), str(item_id), str(path)) for kind, item_id, path in photos + messages]


def backfill_thumbnails(db_path: Path, media_root: Path, force: bool = False) -> dict:
    media_root = media_root.resolve()
    marker = media_root / f".{BACKFILL_ID}.json"
    if marker.is_file() and not force:
        result = json.loads(marker.read_text(encoding="utf-8"))
        result["status"] = "already_completed"
        return result

    media_root.mkdir(parents=True, exist_ok=True)
    result: dict[str, object] = {
        "backfill": BACKFILL_ID,
        "status": "completed",
        "created": 0,
        "existing": 0,
        "missingOriginals": 0,
        "failed": 0,
        "checked": 0,
        "completedAt": utc_timestamp(),
    }
    warnings: list[dict[str, str]] = []

    for kind, item_id, relative_path in referenced_media(db_path):
        result["checked"] = int(result["checked"]) + 1
        source = (media_root / relative_path).resolve()
        if media_root not in source.parents or not source.is_file():
            result["missingOriginals"] = int(result["missingOriginals"]) + 1
            warnings.append({"kind": kind, "id": item_id, "reason": "original_missing"})
            continue
        if thumbnail_path(source).is_file():
            result["existing"] = int(result["existing"]) + 1
            continue
        if ensure_thumbnail(source):
            result["created"] = int(result["created"]) + 1
        else:
            result["failed"] = int(result["failed"]) + 1
            warnings.append({"kind": kind, "id": item_id, "reason": "thumbnail_failed"})

    if warnings:
        result["warnings"] = warnings[:100]
        result["status"] = "completed_with_warnings"

    # A failed conversion commonly means Pillow was unavailable. Do not mark the
    # migration complete so the next deploy can retry after dependencies install.
    if int(result["failed"]) == 0:
        temporary = marker.with_suffix(marker.suffix + ".tmp")
        temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(marker)

    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--media", type=Path, required=True)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    result = backfill_thumbnails(args.db, args.media, force=args.force)
    print(json.dumps(result, sort_keys=True))
    if int(result.get("failed", 0)):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
