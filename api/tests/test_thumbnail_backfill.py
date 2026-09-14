import io
import sqlite3
import tempfile
import unittest
from pathlib import Path

from PIL import Image as PILImage

from app import thumbnail_path
from backfill_thumbnails import backfill_thumbnails


class ThumbnailBackfillTests(unittest.TestCase):
    def test_backfill_creates_referenced_case_and_message_thumbnails_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database_path = root / "customer-flow.sqlite3"
            media_root = root / "media"
            case_directory = media_root / "case-1"
            message_directory = case_directory / "messages"
            message_directory.mkdir(parents=True)

            image = PILImage.effect_noise((1200, 900), 40).convert("RGB")
            encoded = io.BytesIO()
            image.save(encoded, format="JPEG", quality=94)
            case_photo = case_directory / "photo-1.jpg"
            message_photo = message_directory / "message-1.jpg"
            case_photo.write_bytes(encoded.getvalue())
            message_photo.write_bytes(encoded.getvalue())

            with sqlite3.connect(database_path) as connection:
                connection.execute("CREATE TABLE photos (id TEXT, file_path TEXT)")
                connection.execute("CREATE TABLE messages (id TEXT, attachment_path TEXT)")
                connection.execute(
                    "INSERT INTO photos VALUES (?,?)", ("photo-1", "case-1/photo-1.jpg")
                )
                connection.execute(
                    "INSERT INTO messages VALUES (?,?)",
                    ("message-1", "case-1/messages/message-1.jpg"),
                )

            first = backfill_thumbnails(database_path, media_root)
            self.assertEqual("completed", first["status"])
            self.assertEqual(2, first["created"])
            self.assertEqual(2, first["checked"])
            self.assertTrue(thumbnail_path(case_photo).is_file())
            self.assertTrue(thumbnail_path(message_photo).is_file())

            second = backfill_thumbnails(database_path, media_root)
            self.assertEqual("already_completed", second["status"])
            self.assertEqual(2, second["created"])

    def test_backfill_reports_missing_original_without_blocking_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database_path = root / "customer-flow.sqlite3"
            media_root = root / "media"
            media_root.mkdir()
            with sqlite3.connect(database_path) as connection:
                connection.execute("CREATE TABLE photos (id TEXT, file_path TEXT)")
                connection.execute("CREATE TABLE messages (id TEXT, attachment_path TEXT)")
                connection.execute(
                    "INSERT INTO photos VALUES (?,?)", ("missing-photo", "case-1/missing.jpg")
                )

            result = backfill_thumbnails(database_path, media_root)
            self.assertEqual("completed_with_warnings", result["status"])
            self.assertEqual(1, result["missingOriginals"])
            self.assertEqual(0, result["failed"])


if __name__ == "__main__":
    unittest.main()
