#!/usr/bin/env python3
"""Customer Flow local API.

Dependency-free HTTP + SQLite service for the first native vertical slice.
Production deployments must place it behind an HTTPS reverse proxy.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import hmac
import http.client
import json
import os
import secrets
import shutil
import smtplib
import sqlite3
import threading
import unicodedata
import uuid
from datetime import date, datetime, timedelta, timezone
from email.message import EmailMessage
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


API_PREFIX = "/api/v1"
UTC = timezone.utc
IDEMPOTENCY_KEY_ALLOWED = frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
)


def utc_now() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


def iso(value: datetime | str) -> str:
    if isinstance(value, str):
        return value
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def message_text_from_header(value: str | None) -> str:
    if not value:
        return "Annotated patient photo"
    try:
        text = base64.b64decode(value, validate=True).decode("utf-8").strip()
    except (binascii.Error, UnicodeDecodeError):
        raise APIError(422, "invalid_message_text", "The photo note is invalid.")
    if len(text) > 2000:
        raise APIError(422, "message_too_long", "The photo note must be 2,000 characters or fewer.")
    return text or "Annotated patient photo"


def normalize_name(value: str) -> tuple[str, set[str]]:
    folded = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    tokens = {"".join(ch for ch in part.casefold() if ch.isalnum()) for part in folded.split()}
    tokens.discard("")
    return " ".join(sorted(tokens)), tokens


def username_base(value: str) -> str:
    turkish_folded = value.translate(str.maketrans({"ı": "i", "İ": "I"}))
    folded = unicodedata.normalize("NFKD", turkish_folded).encode("ascii", "ignore").decode().casefold()
    parts = [part for part in "".join(ch if ch.isalnum() else " " for ch in folded).split() if part]
    return ".".join(parts)


def pound_amount(value: object) -> str:
    amount = str(value).strip()
    for prefix in ("GBP ", "EUR "):
        if amount.startswith(prefix):
            amount = amount[len(prefix):]
            break
    if amount.startswith(("£", "€")):
        amount = amount[1:]
    return f"£{amount.strip()}"


PATIENT_PROFILE_FIELDS = {
    "dateOfBirth": ("date_of_birth", 10),
    "age": ("stated_age", 3),
    "gender": ("gender", 32),
    "phone": ("phone", 40),
    "email": ("email", 254),
    "address": ("address", 500),
    "occupation": ("occupation", 120),
    "profileNote": ("profile_note", 1000),
}
PATIENT_GENDERS = {"male", "female", "non_binary", "other", "prefer_not_to_say"}


def patient_profile_values(payload: dict, defaults: sqlite3.Row | None = None) -> dict:
    source = payload.get("patientProfile")
    if source is None:
        return {
            column: defaults[column] if defaults is not None and column in defaults.keys() else None
            for column, _ in PATIENT_PROFILE_FIELDS.values()
        }
    if not isinstance(source, dict):
        raise APIError(422, "invalid_patient_profile", "Patient profile information is invalid.")

    result = {}
    for api_name, (column, limit) in PATIENT_PROFILE_FIELDS.items():
        if api_name not in source and defaults is not None and column in defaults.keys():
            result[column] = defaults[column]
            continue
        raw_value = source.get(api_name)
        value = str(raw_value).strip() if raw_value is not None else ""
        value = value or None
        if value and len(value) > limit:
            raise APIError(422, "invalid_patient_profile", f"{api_name} is too long.")
        result[column] = value

    date_of_birth = result["date_of_birth"]
    if date_of_birth:
        try:
            parsed = date.fromisoformat(date_of_birth)
        except ValueError as exc:
            raise APIError(422, "invalid_date_of_birth", "Use YYYY-MM-DD for the date of birth.") from exc
        if parsed > utc_now().date():
            raise APIError(422, "invalid_date_of_birth", "The date of birth cannot be in the future.")
        if parsed.year < 1900:
            raise APIError(422, "invalid_date_of_birth", "Enter a valid date of birth.")

    stated_age = result["stated_age"]
    if stated_age is not None:
        try:
            stated_age = int(stated_age)
        except ValueError as exc:
            raise APIError(422, "invalid_patient_age", "Enter a valid patient age.") from exc
        if not 0 <= stated_age <= 130:
            raise APIError(422, "invalid_patient_age", "Patient age must be between 0 and 130.")
        result["stated_age"] = stated_age

    gender = result["gender"]
    if gender and gender not in PATIENT_GENDERS:
        raise APIError(422, "invalid_gender", "Select a valid gender option.")
    email = result["email"]
    if email and ("@" not in email or email.startswith("@") or email.endswith("@")):
        raise APIError(422, "invalid_patient_email", "Enter a valid patient email address.")
    return result


def patient_age(date_of_birth: str | None, stated_age: int | None = None) -> int | None:
    if date_of_birth:
        born = date.fromisoformat(date_of_birth)
        today = utc_now().date()
        return today.year - born.year - ((today.month, today.day) < (born.month, born.day))
    return stated_age


def hash_password(password: str, salt: bytes | None = None) -> tuple[str, str]:
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 210_000)
    return salt.hex(), digest.hex()


def validate_idempotency_key(value: str | None) -> str | None:
    """Validate an optional caller-provided key used to deduplicate writes."""
    if value is None:
        return None
    key = value.strip()
    if not 8 <= len(key) <= 128 or any(ch not in IDEMPOTENCY_KEY_ALLOWED for ch in key):
        raise APIError(
            422,
            "invalid_idempotency_key",
            "Idempotency-Key must be 8-128 characters using letters, numbers, '.', '_', ':' or '-'.",
        )
    return key


def request_fingerprint(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return hashlib.sha256(encoded).hexdigest()


def mcp_token_hash(token: str) -> str:
    """Hash a high-entropy agency MCP token before persistent storage."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def public_mcp_url() -> str:
    base_url = os.getenv("CF_PUBLIC_BASE_URL", "https://flow.drascom.uk").strip().rstrip("/")
    parsed = urlparse(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc or parsed.query or parsed.fragment:
        raise RuntimeError("CF_PUBLIC_BASE_URL must be an absolute HTTP(S) URL without a query or fragment.")
    return f"{base_url}/mcp"


class APIError(Exception):
    def __init__(self, status: int, code: str, message: str, details: object | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details


class IdempotentReplay(dict):
    """Marks a stored mutation response so the HTTP layer does not publish it again."""


class ChangeBroker:
    """Process-local change signal used by authenticated long-poll clients."""

    def __init__(self) -> None:
        self._condition = threading.Condition()
        self._revision = 0
        self._latest_event: dict | None = None

    def publish(self, kind: str, entity_id: str | None, actor_id: str) -> None:
        with self._condition:
            self._revision += 1
            self._latest_event = {
                "kind": kind,
                "entityID": entity_id,
                "actorID": actor_id,
                "occurredAt": iso(utc_now()),
            }
            self._condition.notify_all()

    def wait(self, since: int, timeout: float = 15.0) -> dict:
        with self._condition:
            self._condition.wait_for(lambda: self._revision != since, timeout=timeout)
            changed = self._revision != since
            return {
                "revision": self._revision,
                "changed": changed,
                "event": self._latest_event if changed else None,
            }


SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS agencies (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE COLLATE NOCASE,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('doctor','agent','admin','manager')),
  password_salt TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  agency_id TEXT REFERENCES agencies(id),
  email TEXT,
  phone TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS agency_mcp_credentials (
  agency_id TEXT PRIMARY KEY REFERENCES agencies(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  service_user_id TEXT NOT NULL UNIQUE REFERENCES users(id),
  created_at TEXT NOT NULL,
  rotated_at TEXT NOT NULL,
  rotated_by TEXT NOT NULL REFERENCES users(id)
);
CREATE TABLE IF NOT EXISTS password_reset_codes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_salt TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  consumed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_password_resets_user ON password_reset_codes(user_id, created_at);
CREATE TABLE IF NOT EXISTS patients (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  assigned_doctor_id TEXT REFERENCES users(id),
  profile_photo_path TEXT,
  date_of_birth TEXT,
  stated_age INTEGER,
  gender TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  occupation TEXT,
  profile_note TEXT,
  last_updated TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_patients_normalized_name ON patients(normalized_name);
CREATE TABLE IF NOT EXISTS cases (
  id TEXT PRIMARY KEY,
  reference TEXT NOT NULL UNIQUE,
  patient_id TEXT NOT NULL REFERENCES patients(id),
  agent_id TEXT NOT NULL REFERENCES users(id),
  assigned_doctor_id TEXT REFERENCES users(id),
  uploaded_at TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('waiting','answered','closed')),
  photo_count INTEGER NOT NULL DEFAULT 0,
  agent_note TEXT NOT NULL,
  agent_grafts TEXT NOT NULL,
  currency TEXT NOT NULL,
  agent_price TEXT NOT NULL,
  final_grafts TEXT,
  final_price TEXT,
  finalized_at TEXT,
  finalized_by TEXT REFERENCES users(id),
  version INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_cases_doctor_status ON cases(assigned_doctor_id, status);
CREATE INDEX IF NOT EXISTS idx_cases_agent ON cases(agent_id, uploaded_at);
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users(id),
  author_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('doctor','agent','admin','system')),
  created_at TEXT NOT NULL,
  text TEXT NOT NULL,
  approximate_grafts TEXT,
  recommended_price TEXT,
  attachment_path TEXT,
  attachment_content_type TEXT,
  deleted_at TEXT,
  deleted_by TEXT REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_messages_case_time ON messages(case_id, created_at);
CREATE TABLE IF NOT EXISTS photos (
  id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  file_path TEXT,
  content_type TEXT,
  uploaded_by TEXT NOT NULL REFERENCES users(id),
  uploaded_at TEXT NOT NULL,
  deleted_at TEXT,
  deleted_by TEXT REFERENCES users(id),
  UNIQUE(case_id, position)
);
CREATE TABLE IF NOT EXISTS audit_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  detail_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS idempotency_records (
  actor_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operation TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(actor_id, operation, idempotency_key)
);
CREATE TABLE IF NOT EXISTS counters (
  name TEXT PRIMARY KEY,
  value INTEGER NOT NULL
);
INSERT OR IGNORE INTO counters(name, value) VALUES ('case_reference', 240900);
INSERT OR IGNORE INTO counters(name, value) VALUES ('patient_reference', 1100);
"""


class Database:
    def __init__(self, path: Path, media_root: Path):
        self.path = path
        self.media_root = media_root
        self._init_lock = threading.Lock()

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=15, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        return conn

    def initialize(self, seed: bool = True) -> None:
        with self._init_lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.media_root.mkdir(parents=True, exist_ok=True)
            with self.connect() as conn:
                conn.executescript(SCHEMA)
                columns = {row["name"] for row in conn.execute("PRAGMA table_info(users)").fetchall()}
                if "agency_id" not in columns:
                    conn.execute("ALTER TABLE users ADD COLUMN agency_id TEXT REFERENCES agencies(id)")
                if "email" not in columns:
                    conn.execute("ALTER TABLE users ADD COLUMN email TEXT")
                if "phone" not in columns:
                    conn.execute("ALTER TABLE users ADD COLUMN phone TEXT")
                patient_columns = {row["name"] for row in conn.execute("PRAGMA table_info(patients)").fetchall()}
                patient_profile_columns = {
                    "date_of_birth": "TEXT", "stated_age": "INTEGER", "gender": "TEXT", "phone": "TEXT",
                    "email": "TEXT", "address": "TEXT", "occupation": "TEXT", "profile_note": "TEXT",
                }
                for column, column_type in patient_profile_columns.items():
                    if column not in patient_columns:
                        conn.execute(f"ALTER TABLE patients ADD COLUMN {column} {column_type}")
                photo_columns = {row["name"] for row in conn.execute("PRAGMA table_info(photos)").fetchall()}
                if "deleted_at" not in photo_columns:
                    conn.execute("ALTER TABLE photos ADD COLUMN deleted_at TEXT")
                if "deleted_by" not in photo_columns:
                    conn.execute("ALTER TABLE photos ADD COLUMN deleted_by TEXT REFERENCES users(id)")
                message_columns = {row["name"] for row in conn.execute("PRAGMA table_info(messages)").fetchall()}
                if "attachment_path" not in message_columns:
                    conn.execute("ALTER TABLE messages ADD COLUMN attachment_path TEXT")
                if "attachment_content_type" not in message_columns:
                    conn.execute("ALTER TABLE messages ADD COLUMN attachment_content_type TEXT")
                if "deleted_at" not in message_columns:
                    conn.execute("ALTER TABLE messages ADD COLUMN deleted_at TEXT")
                if "deleted_by" not in message_columns:
                    conn.execute("ALTER TABLE messages ADD COLUMN deleted_by TEXT REFERENCES users(id)")
                case_columns = {row["name"] for row in conn.execute("PRAGMA table_info(cases)").fetchall()}
                if "final_grafts" not in case_columns:
                    conn.execute("ALTER TABLE cases ADD COLUMN final_grafts TEXT")
                if "final_price" not in case_columns:
                    conn.execute("ALTER TABLE cases ADD COLUMN final_price TEXT")
                if "finalized_at" not in case_columns:
                    conn.execute("ALTER TABLE cases ADD COLUMN finalized_at TEXT")
                if "finalized_by" not in case_columns:
                    conn.execute("ALTER TABLE cases ADD COLUMN finalized_by TEXT REFERENCES users(id)")
                conn.execute("DELETE FROM photos WHERE file_path IS NULL")
                conn.execute(
                    "UPDATE cases SET photo_count=(SELECT COUNT(*) FROM photos p "
                    "WHERE p.case_id=cases.id AND p.file_path IS NOT NULL AND p.deleted_at IS NULL)"
                )
                conn.execute(
                    "UPDATE cases SET final_grafts=agent_grafts,final_price=agent_price,"
                    "finalized_at=uploaded_at,finalized_by=agent_id "
                    "WHERE status='closed' AND final_grafts IS NULL"
                )
                conn.execute("UPDATE cases SET currency='GBP' WHERE currency <> 'GBP'")
                conn.execute(
                    "UPDATE messages SET recommended_price = CASE "
                    "WHEN recommended_price LIKE '£%' THEN recommended_price "
                    "WHEN recommended_price LIKE '€%' THEN '£' || SUBSTR(recommended_price, 2) "
                    "WHEN recommended_price LIKE 'EUR %' THEN '£' || SUBSTR(recommended_price, 5) "
                    "WHEN recommended_price LIKE 'GBP %' THEN '£' || SUBSTR(recommended_price, 5) "
                    "ELSE '£' || recommended_price END "
                    "WHERE recommended_price IS NOT NULL AND TRIM(recommended_price) <> ''"
                )
                self._ensure_manager_role(conn)
                self._ensure_admin_message_role(conn)
                conn.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email COLLATE NOCASE) "
                    "WHERE email IS NOT NULL AND email <> ''"
                )
            self.ensure_demo_agencies()
            if seed:
                self.seed_demo()

    @staticmethod
    def _ensure_manager_role(conn: sqlite3.Connection) -> None:
        table_sql = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='users'"
        ).fetchone()[0]
        if "'manager'" in table_sql:
            return
        conn.execute("PRAGMA foreign_keys = OFF")
        conn.execute("BEGIN IMMEDIATE")
        try:
            conn.execute(
                "CREATE TABLE users_migrated ("
                "id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE, "
                "display_name TEXT NOT NULL, "
                "role TEXT NOT NULL CHECK(role IN ('doctor','agent','admin','manager')), "
                "password_salt TEXT NOT NULL, password_hash TEXT NOT NULL, "
                "agency_id TEXT REFERENCES agencies(id), email TEXT, phone TEXT, "
                "active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)"
            )
            conn.execute(
                "INSERT INTO users_migrated "
                "SELECT id,username,display_name,role,password_salt,password_hash,agency_id,email,phone,active,created_at "
                "FROM users"
            )
            conn.execute("DROP TABLE users")
            conn.execute("ALTER TABLE users_migrated RENAME TO users")
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.execute("PRAGMA foreign_keys = ON")

    @staticmethod
    def _ensure_admin_message_role(conn: sqlite3.Connection) -> None:
        table_sql = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='messages'"
        ).fetchone()[0]
        if "'admin'" in table_sql:
            return
        conn.execute("PRAGMA foreign_keys = OFF")
        conn.execute("BEGIN IMMEDIATE")
        try:
            conn.execute(
                "CREATE TABLE messages_migrated ("
                "id TEXT PRIMARY KEY, case_id TEXT NOT NULL REFERENCES cases(id) ON DELETE CASCADE, "
                "author_id TEXT NOT NULL REFERENCES users(id), author_name TEXT NOT NULL, "
                "role TEXT NOT NULL CHECK(role IN ('doctor','agent','admin','system')), "
                "created_at TEXT NOT NULL, text TEXT NOT NULL, approximate_grafts TEXT, "
                "recommended_price TEXT, attachment_path TEXT, attachment_content_type TEXT, "
                "deleted_at TEXT, deleted_by TEXT REFERENCES users(id))"
            )
            conn.execute(
                "INSERT INTO messages_migrated "
                "SELECT id,case_id,author_id,author_name,role,created_at,text,approximate_grafts,"
                "recommended_price,attachment_path,attachment_content_type,deleted_at,deleted_by FROM messages"
            )
            conn.execute("DROP TABLE messages")
            conn.execute("ALTER TABLE messages_migrated RENAME TO messages")
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_messages_case_time ON messages(case_id, created_at)"
            )
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.execute("PRAGMA foreign_keys = ON")

    def ensure_demo_agencies(self) -> None:
        now = iso(utc_now())
        agencies = [
            ("agency-drascom", "Acenta 1"),
            ("agency-north", "Acenta 2"),
        ]
        with self.connect() as conn:
            for agency_id, name in agencies:
                conn.execute("INSERT OR IGNORE INTO agencies VALUES (?,?,1,?)", (agency_id, name, now))
            conn.execute("UPDATE users SET agency_id='agency-drascom' WHERE username='user1' AND agency_id IS NULL")
            conn.execute("UPDATE users SET agency_id='agency-north' WHERE username='user2' AND agency_id IS NULL")

    def seed_demo(self) -> None:
        with self.connect() as conn:
            if conn.execute("SELECT 1 FROM users LIMIT 1").fetchone():
                return
            now = iso(utc_now())
            demo_users = [
                ("doctor-emre", "doctor1", "Doctor 1", "doctor", None, os.getenv("CF_DOCTOR_PASSWORD", "demo123")),
                ("doctor-two", "doctor2", "Doctor 2", "doctor", None, os.getenv("CF_DOCTOR2_PASSWORD", "demo123")),
                ("agent-selin", "user1", "Selin Arslan", "agent", "agency-drascom", os.getenv("CF_AGENT_PASSWORD", "demo123")),
                ("agent-mert", "user2", "Mert Demir", "agent", "agency-north", os.getenv("CF_AGENT2_PASSWORD", "demo123")),
                ("manager-local", "manager", "Local Manager", "manager", None, os.getenv("CF_MANAGER_PASSWORD", "demo123")),
                ("admin-local", "admin", "Local Admin", "admin", None, os.getenv("CF_ADMIN_PASSWORD", "demo123")),
            ]
            conn.execute("BEGIN IMMEDIATE")
            try:
                for user_id, username, display_name, role, agency_id, password in demo_users:
                    salt, digest = hash_password(password)
                    conn.execute(
                        "INSERT INTO users(id,username,display_name,role,password_salt,password_hash,agency_id,active,created_at) VALUES (?,?,?,?,?,?,?,1,?)",
                        (user_id, username, display_name, role, salt, digest, agency_id, now),
                    )
                cases = [
                    ("HT-240814", "PT-1042", "Daniel Morris", "agent-selin", "doctor-emre", 8, "waiting", 4, "3,200", "2,850", "Diffuse thinning across the frontal and mid-scalp area. Please assess the graft range and whether the crown should be planned for the same session.", False),
                    ("HT-240825", "PT-1071", "Ayhan Çolak", "agent-mert", "doctor-emre", 12, "waiting", 3, "2,700", "2,550", "Frontal hairline restoration request with progressive temporal recession. Please review the donor area and proposed graft range.", False),
                    ("HT-240817", "PT-1051", "Liam Wilson", "agent-mert", "doctor-emre", 5, "waiting", 3, "2,400", "2,350", "Patient requests a conservative frontal hairline. No previous surgery. Please advise whether medical stabilisation is recommended first.", False),
                    ("HT-240821", "PT-1060", "Ethan Cole", "agent-selin", None, 2, "waiting", 4, "1,800", "2,100", "Second opinion requested after a previous FUE procedure. Please review corrective options.", False),
                    ("HT-240803", "PT-1037", "Noah Bennett", "agent-selin", "doctor-emre", 28, "answered", 3, "2,600", "2,500", "Receding hairline with good donor density. Recommendation is waiting for agent confirmation.", True),
                    ("HT-240799", "PT-1029", "Oliver Grant", "agent-mert", "doctor-emre", 48, "answered", 4, "3,000", "2,800", "Crown-focused case. Recommendation has been sent.", True),
                    ("HT-240764", "PT-0998", "George Hall", "agent-selin", "doctor-emre", 96, "closed", 3, "2,200", "2,300", "Frontal restoration consultation completed and confirmed.", True),
                ]
                for row in cases:
                    self._seed_case(conn, *row)
                conn.execute("COMMIT")
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def _seed_case(self, conn: sqlite3.Connection, reference: str, patient_id: str, patient_name: str,
                   agent_id: str, doctor_id: str | None, hours_ago: int, status: str, photo_count: int,
                   grafts: str, price: str, note: str, doctor_reply: bool) -> None:
        created = utc_now() - timedelta(hours=hours_ago)
        normalized, _ = normalize_name(patient_name)
        conn.execute(
            "INSERT INTO patients(id,name,normalized_name,assigned_doctor_id,profile_photo_path,last_updated) "
            "VALUES (?,?,?,?,NULL,?)",
            (patient_id, patient_name, normalized, doctor_id, iso(created)),
        )
        case_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"customer-flow:{reference}"))
        final_grafts = grafts if status == "closed" else None
        final_price = price if status == "closed" else None
        finalized_at = iso(created) if status == "closed" else None
        finalized_by = agent_id if status == "closed" else None
        conn.execute(
            "INSERT INTO cases("
            "id,reference,patient_id,agent_id,assigned_doctor_id,uploaded_at,status,photo_count,"
            "agent_note,agent_grafts,currency,agent_price,final_grafts,final_price,finalized_at,finalized_by,version"
            ") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1)",
            (
                case_id, reference, patient_id, agent_id, doctor_id, iso(created), status, 0,
                note, grafts, "GBP", price, final_grafts, final_price, finalized_at, finalized_by,
            ),
        )
        agent = conn.execute("SELECT display_name FROM users WHERE id=?", (agent_id,)).fetchone()[0]
        conn.execute(
            "INSERT INTO messages(id,case_id,author_id,author_name,role,created_at,text,approximate_grafts,recommended_price) VALUES (?,?,?,?,?,?,?,?,?)",
            (str(uuid.uuid4()), case_id, agent_id, agent, "agent", iso(created), "Patient photos and consultation information uploaded.", None, None),
        )
        if doctor_reply:
            conn.execute(
                "INSERT INTO messages(id,case_id,author_id,author_name,role,created_at,text,approximate_grafts,recommended_price) VALUES (?,?,?,?,?,?,?,?,?)",
                (str(uuid.uuid4()), case_id, "doctor-emre", "Doctor 1", "doctor", iso(created + timedelta(hours=1)),
                 "The donor area appears suitable, subject to an in-person density measurement.", "2,400–2,700", "£2,600"),
            )

    def login(self, username: str, password: str) -> dict:
        with self.connect() as conn:
            user = conn.execute("SELECT * FROM users WHERE username=? AND active=1", (username.strip(),)).fetchone()
            if not user:
                raise APIError(401, "invalid_credentials", "Username or password is incorrect.")
            _, candidate = hash_password(password, bytes.fromhex(user["password_salt"]))
            if not hmac.compare_digest(candidate, user["password_hash"]):
                raise APIError(401, "invalid_credentials", "Username or password is incorrect.")
            token = secrets.token_urlsafe(32)
            expires = utc_now() + timedelta(days=7)
            conn.execute(
                "INSERT INTO sessions VALUES (?,?,?,?)",
                (hashlib.sha256(token.encode()).hexdigest(), user["id"], iso(utc_now()), iso(expires)),
            )
            return {"token": token, "expiresAt": iso(expires), "user": self._public_user(user)}

    def authenticate(self, token: str) -> sqlite3.Row:
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        with self.connect() as conn:
            row = conn.execute(
                "SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id "
                "WHERE s.token_hash=? AND s.expires_at>? AND u.active=1",
                (token_hash, iso(utc_now())),
            ).fetchone()
            if not row:
                raise APIError(401, "invalid_session", "Your session is invalid or has expired.")
            return row

    def logout(self, token: str) -> None:
        with self.connect() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash=?", (hashlib.sha256(token.encode()).hexdigest(),))

    @staticmethod
    def _public_user(row: sqlite3.Row) -> dict:
        return {
            "id": row["id"], "username": row["username"], "displayName": row["display_name"],
            "role": row["role"], "agencyID": row["agency_id"] if "agency_id" in row.keys() else None,
            "email": row["email"] if "email" in row.keys() else None,
            "phone": row["phone"] if "phone" in row.keys() else None,
        }

    def update_profile(self, payload: dict, user: sqlite3.Row) -> dict:
        display_name = str(payload.get("displayName", user["display_name"])).strip()
        email = str(payload.get("email", user["email"] or "")).strip().casefold()
        phone = str(payload.get("phone", user["phone"] or "")).strip()
        if len(display_name) < 2 or len(display_name) > 120:
            raise APIError(422, "invalid_display_name", "Enter a valid display name.")
        if email and (len(email) > 254 or "@" not in email or email.startswith("@") or email.endswith("@")):
            raise APIError(422, "invalid_email", "Enter a valid email address.")
        if phone and (len(phone) > 30 or sum(ch.isdigit() for ch in phone) < 7):
            raise APIError(422, "invalid_phone", "Enter a valid phone number.")
        with self.connect() as conn:
            try:
                conn.execute(
                    "UPDATE users SET display_name=?, email=?, phone=? WHERE id=?",
                    (display_name, email or None, phone or None, user["id"]),
                )
            except sqlite3.IntegrityError:
                raise APIError(409, "email_exists", "This email address is already used by another account.")
            updated = conn.execute("SELECT * FROM users WHERE id=?", (user["id"],)).fetchone()
            self._audit(conn, user["id"], "profile.updated", "user", user["id"],
                        {"emailChanged": email != (user["email"] or ""), "phoneChanged": phone != (user["phone"] or "")})
            return self._public_user(updated)

    def change_password(self, payload: dict, user: sqlite3.Row, token: str) -> dict:
        current_password = str(payload.get("currentPassword", ""))
        new_password = str(payload.get("newPassword", ""))
        if len(new_password) < 10:
            raise APIError(422, "weak_password", "The new password must be at least 10 characters.")
        _, candidate = hash_password(current_password, bytes.fromhex(user["password_salt"]))
        if not hmac.compare_digest(candidate, user["password_hash"]):
            raise APIError(403, "incorrect_password", "The current password is incorrect.")
        if hmac.compare_digest(current_password, new_password):
            raise APIError(422, "password_unchanged", "Choose a different password.")
        salt, digest = hash_password(new_password)
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        with self.connect() as conn:
            conn.execute("UPDATE users SET password_salt=?, password_hash=? WHERE id=?", (salt, digest, user["id"]))
            conn.execute("DELETE FROM sessions WHERE user_id=? AND token_hash<>?", (user["id"], token_hash))
            self._audit(conn, user["id"], "password.changed", "user", user["id"], {})
        return {"ok": True}

    @staticmethod
    def _send_password_reset_email(address: str, display_name: str, code: str) -> None:
        host = os.getenv("CF_SMTP_HOST", "").strip()
        test_code = os.getenv("CF_PASSWORD_RESET_TEST_CODE", "").strip()
        if test_code:
            return
        if not host:
            raise APIError(503, "reset_delivery_unavailable",
                           "Password reset delivery is not configured. Contact your administrator.")
        use_ssl = os.getenv("CF_SMTP_SSL", "1") != "0"
        port = int(os.getenv("CF_SMTP_PORT", "465" if use_ssl else "587"))
        username = os.getenv("CF_SMTP_USERNAME", "").strip()
        password = os.getenv("CF_SMTP_PASSWORD", "")
        sender = os.getenv("CF_SMTP_FROM", username or "no-reply@customerflow.local")
        message = EmailMessage()
        message["Subject"] = "Customer Flow password reset code"
        message["From"] = sender
        message["To"] = address
        message.set_content(
            f"Hello {display_name},\n\nYour Customer Flow password reset code is: {code}\n\n"
            "This code expires in 10 minutes. If you did not request it, you can ignore this message.\n"
        )
        smtp_class = smtplib.SMTP_SSL if use_ssl else smtplib.SMTP
        with smtp_class(host, port, timeout=15) as smtp:
            if not use_ssl and os.getenv("CF_SMTP_STARTTLS", "1") != "0":
                smtp.starttls()
            if username:
                smtp.login(username, password)
            smtp.send_message(message)

    def request_password_reset(self, payload: dict) -> dict:
        identifier = str(payload.get("identifier", "")).strip()
        generic = {"ok": True, "message": "If the account can be verified, a reset code has been sent."}
        if len(identifier) < 2:
            return generic
        if not os.getenv("CF_SMTP_HOST", "").strip() and not os.getenv("CF_PASSWORD_RESET_TEST_CODE", "").strip():
            raise APIError(503, "reset_delivery_unavailable",
                           "Password reset delivery is not configured. Contact your administrator.")
        with self.connect() as conn:
            user = conn.execute(
                "SELECT * FROM users WHERE active=1 AND (username=? COLLATE NOCASE OR email=? COLLATE NOCASE)",
                (identifier, identifier),
            ).fetchone()
            if not user or not user["email"]:
                return generic
            recent = conn.execute(
                "SELECT COUNT(*) FROM password_reset_codes WHERE user_id=? AND created_at>?",
                (user["id"], iso(utc_now() - timedelta(hours=1))),
            ).fetchone()[0]
            if recent >= 5:
                raise APIError(429, "too_many_reset_requests", "Too many reset requests. Try again later.")
            code = os.getenv("CF_PASSWORD_RESET_TEST_CODE", "").strip() or f"{secrets.randbelow(1_000_000):06d}"
            salt, digest = hash_password(code)
            reset_id = str(uuid.uuid4())
            created = utc_now()
            self._send_password_reset_email(user["email"], user["display_name"], code)
            conn.execute(
                "INSERT INTO password_reset_codes(id,user_id,code_salt,code_hash,created_at,expires_at) VALUES (?,?,?,?,?,?)",
                (reset_id, user["id"], salt, digest, iso(created), iso(created + timedelta(minutes=10))),
            )
            self._audit(conn, user["id"], "password.reset_requested", "user", user["id"], {})
        return generic

    def reset_password(self, payload: dict) -> dict:
        identifier = str(payload.get("identifier", "")).strip()
        code = str(payload.get("code", "")).strip()
        new_password = str(payload.get("newPassword", ""))
        if len(new_password) < 10:
            raise APIError(422, "weak_password", "The new password must be at least 10 characters.")
        if len(code) != 6 or not code.isdigit():
            raise APIError(422, "invalid_reset_code", "The reset code is invalid or has expired.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                user = conn.execute(
                    "SELECT * FROM users WHERE active=1 AND (username=? COLLATE NOCASE OR email=? COLLATE NOCASE)",
                    (identifier, identifier),
                ).fetchone()
                reset = None if not user else conn.execute(
                    "SELECT * FROM password_reset_codes WHERE user_id=? AND consumed_at IS NULL AND expires_at>? "
                    "ORDER BY created_at DESC LIMIT 1",
                    (user["id"], iso(utc_now())),
                ).fetchone()
                if not user or not reset or reset["attempts"] >= 5:
                    raise APIError(422, "invalid_reset_code", "The reset code is invalid or has expired.")
                _, candidate = hash_password(code, bytes.fromhex(reset["code_salt"]))
                if not hmac.compare_digest(candidate, reset["code_hash"]):
                    conn.execute("UPDATE password_reset_codes SET attempts=attempts+1 WHERE id=?", (reset["id"],))
                    conn.execute("COMMIT")
                    raise APIError(422, "invalid_reset_code", "The reset code is invalid or has expired.")
                salt, digest = hash_password(new_password)
                conn.execute("UPDATE users SET password_salt=?, password_hash=? WHERE id=?", (salt, digest, user["id"]))
                conn.execute("UPDATE password_reset_codes SET consumed_at=? WHERE id=?", (iso(utc_now()), reset["id"]))
                conn.execute("DELETE FROM sessions WHERE user_id=?", (user["id"],))
                self._audit(conn, user["id"], "password.reset_completed", "user", user["id"], {})
                conn.execute("COMMIT")
                return {"ok": True}
            except APIError:
                if conn.in_transaction:
                    conn.execute("ROLLBACK")
                raise
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def fetch_cases(self, user: sqlite3.Row) -> list[dict]:
        where, params = "", []
        if user["role"] == "agent":
            if user["agency_id"]:
                where, params = "WHERE u.agency_id=?", [user["agency_id"]]
            else:
                where, params = "WHERE c.agent_id=?", [user["id"]]
        with self.connect() as conn:
            rows = conn.execute(
                f"SELECT c.*, p.name patient_name, p.assigned_doctor_id patient_doctor, p.last_updated, "
                f"p.date_of_birth,p.stated_age,p.gender,p.phone,p.email,p.address,p.occupation,p.profile_note, "
                f"u.display_name agent_name, a.name agency_name FROM cases c JOIN patients p ON p.id=c.patient_id "
                f"JOIN users u ON u.id=c.agent_id LEFT JOIN agencies a ON a.id=u.agency_id "
                f"{where} ORDER BY c.uploaded_at ASC",
                params,
            ).fetchall()
            return [self._case_json(conn, row) for row in rows]

    def get_case(self, case_id: str, user: sqlite3.Row) -> dict:
        with self.connect() as conn:
            row = self._case_row(conn, case_id)
            self._assert_case_visible(row, user)
            return self._case_json(conn, row)

    def find_matches(self, name: str, user: sqlite3.Row) -> list[dict]:
        self._require_role(user, "agent")
        _, query_tokens = normalize_name(name)
        if len(query_tokens) < 2:
            return []
        with self.connect() as conn:
            if user["agency_id"]:
                patients = conn.execute(
                    "SELECT DISTINCT p.* FROM patients p JOIN cases c ON c.patient_id=p.id "
                    "JOIN users u ON u.id=c.agent_id WHERE u.agency_id=? ORDER BY p.last_updated DESC",
                    (user["agency_id"],),
                ).fetchall()
            else:
                patients = conn.execute(
                    "SELECT DISTINCT p.* FROM patients p JOIN cases c ON c.patient_id=p.id "
                    "WHERE c.agent_id=? ORDER BY p.last_updated DESC",
                    (user["id"],),
                ).fetchall()
            result = []
            for patient in patients:
                _, patient_tokens = normalize_name(patient["name"])
                if not query_tokens.issubset(patient_tokens):
                    continue
                latest = conn.execute(
                    "SELECT c.*, a.display_name agent_name FROM cases c JOIN users a ON a.id=c.agent_id "
                    "WHERE c.patient_id=? AND "
                    + ("a.agency_id=? " if user["agency_id"] else "c.agent_id=? ")
                    + "ORDER BY c.uploaded_at DESC LIMIT 1",
                    (patient["id"], user["agency_id"] or user["id"]),
                ).fetchone()
                doctor = None
                if patient["assigned_doctor_id"]:
                    doctor_row = conn.execute("SELECT display_name FROM users WHERE id=?", (patient["assigned_doctor_id"],)).fetchone()
                    doctor = doctor_row[0] if doctor_row else None
                result.append({
                    "id": patient["id"], "name": patient["name"], "assignedDoctorName": doctor,
                    "lastUpdated": patient["last_updated"], "createdByAnotherAgent": latest["agent_id"] != user["id"],
                    "photoCount": latest["photo_count"],
                })
            return result

    def create_case(
        self,
        payload: dict,
        user: sqlite3.Row,
        idempotency_key: str | None = None,
    ) -> dict:
        self._require_role(user, "agent")
        idempotency_key = validate_idempotency_key(idempotency_key)
        fingerprint = request_fingerprint(payload)
        required = ["patientName", "grafts", "currency", "price", "note", "photoCount"]
        missing = [key for key in required if payload.get(key) in (None, "")]
        if missing:
            raise APIError(422, "missing_fields", "Required case information is missing.", missing)
        name = str(payload["patientName"]).strip()
        normalized, query_tokens = normalize_name(name)
        if len(query_tokens) < 2:
            raise APIError(422, "full_name_required", "Enter the patient's first and last name.")
        profile = patient_profile_values(payload)
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                replay = self._idempotency_replay(
                    conn, user["id"], "case.create", idempotency_key, fingerprint
                )
                if replay is not None:
                    replayed = IdempotentReplay(self._case_json(conn, self._case_row(conn, replay)))
                    conn.execute("COMMIT")
                    return replayed
                if user["agency_id"]:
                    candidates = conn.execute(
                        "SELECT DISTINCT p.id,p.name FROM patients p JOIN cases c ON c.patient_id=p.id "
                        "JOIN users u ON u.id=c.agent_id WHERE p.normalized_name=? AND u.agency_id=?",
                        (normalized, user["agency_id"]),
                    ).fetchall()
                else:
                    candidates = conn.execute(
                        "SELECT DISTINCT p.id,p.name FROM patients p JOIN cases c ON c.patient_id=p.id "
                        "WHERE p.normalized_name=? AND c.agent_id=?",
                        (normalized, user["id"]),
                    ).fetchall()
                existing_id = payload.get("existingPatientID")
                confirmed_different = bool(payload.get("duplicateConfirmedDifferent"))
                if candidates and not existing_id and not confirmed_different:
                    raise APIError(409, "duplicate_confirmation_required", "A previous consultation may exist for this patient.",
                                   [{"id": row["id"], "name": row["name"]} for row in candidates])
                if existing_id:
                    if user["agency_id"]:
                        patient = conn.execute(
                            "SELECT DISTINCT p.* FROM patients p JOIN cases c ON c.patient_id=p.id "
                            "JOIN users u ON u.id=c.agent_id WHERE p.id=? AND u.agency_id=?",
                            (existing_id, user["agency_id"]),
                        ).fetchone()
                    else:
                        patient = conn.execute(
                            "SELECT DISTINCT p.* FROM patients p JOIN cases c ON c.patient_id=p.id "
                            "WHERE p.id=? AND c.agent_id=?",
                            (existing_id, user["id"]),
                        ).fetchone()
                    if not patient:
                        raise APIError(404, "patient_not_found", "The selected patient could not be found.")
                    patient_id = patient["id"]
                    assigned_doctor = patient["assigned_doctor_id"]
                    conn.execute("UPDATE patients SET last_updated=? WHERE id=?", (iso(utc_now()), patient_id))
                else:
                    patient_id = self._next_reference(conn, "patient_reference", "PT-")
                    assigned_doctor = None
                    conn.execute(
                        "INSERT INTO patients("
                        "id,name,normalized_name,assigned_doctor_id,profile_photo_path,date_of_birth,stated_age,gender,"
                        "phone,email,address,occupation,profile_note,last_updated"
                        ") VALUES (?,?,?,?,NULL,?,?,?,?,?,?,?,?,?)",
                        (
                            patient_id, name, normalized, None, profile["date_of_birth"], profile["stated_age"],
                            profile["gender"], profile["phone"], profile["email"], profile["address"],
                            profile["occupation"], profile["profile_note"], iso(utc_now()),
                        ),
                    )
                case_id = str(uuid.uuid4())
                reference = self._next_reference(conn, "case_reference", "HT-")
                now = iso(utc_now())
                requested_photo_count = max(0, int(payload["photoCount"]))
                conn.execute(
                    "INSERT INTO cases("
                    "id,reference,patient_id,agent_id,assigned_doctor_id,uploaded_at,status,photo_count,"
                    "agent_note,agent_grafts,currency,agent_price,version"
                    ") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,1)",
                    (case_id, reference, patient_id, user["id"], assigned_doctor, now, "waiting", 0,
                     str(payload["note"]), str(payload["grafts"]), "GBP", str(payload["price"])),
                )
                conn.execute("INSERT INTO messages(id,case_id,author_id,author_name,role,created_at,text,approximate_grafts,recommended_price) VALUES (?,?,?,?,?,?,?,?,?)",
                             (str(uuid.uuid4()), case_id, user["id"], user["display_name"], "agent", now,
                              "Patient photos and consultation information uploaded.", None, None))
                self._audit(conn, user["id"], "case.created", "case", case_id,
                            {"reference": reference, "duplicateConfirmedDifferent": confirmed_different,
                             "requestedPhotoCount": requested_photo_count})
                row = self._case_row(conn, case_id)
                result = self._case_json(conn, row)
                self._store_idempotency_result(
                    conn, user["id"], "case.create", idempotency_key, fingerprint, case_id
                )
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def send_recommendation(self, case_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "doctor")
        text = str(payload.get("text", "")).strip()
        if not text:
            raise APIError(422, "message_required", "Enter a message.")
        approximate_grafts = str(payload.get("approximateGrafts") or "").strip() or None
        raw_price = str(payload.get("recommendedPrice") or "").strip()
        recommended_price = pound_amount(raw_price) if raw_price else None
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = self._case_row(conn, case_id)
                if row["status"] == "closed":
                    raise APIError(409, "case_closed", "A closed case cannot receive new messages.")
                if row["assigned_doctor_id"] not in (None, user["id"]):
                    raise APIError(409, "case_changed", "This case is assigned to another doctor. Refresh to continue.")
                now = iso(utc_now())
                conn.execute("UPDATE cases SET assigned_doctor_id=?, status='answered', version=version+1 WHERE id=?",
                             (user["id"], case_id))
                conn.execute("UPDATE patients SET assigned_doctor_id=?, last_updated=? WHERE id=?",
                             (user["id"], now, row["patient_id"]))
                conn.execute("INSERT INTO messages(id,case_id,author_id,author_name,role,created_at,text,approximate_grafts,recommended_price) VALUES (?,?,?,?,?,?,?,?,?)",
                             (str(uuid.uuid4()), case_id, user["id"], user["display_name"], "doctor", now,
                              text, approximate_grafts, recommended_price))
                self._audit(conn, user["id"], "case.doctor_message_added", "case", case_id, {
                    "includesGrafts": approximate_grafts is not None,
                    "includesPrice": recommended_price is not None,
                })
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def save_agent_values(self, case_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "agent")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = self._case_row(conn, case_id)
                self._assert_owner(row, user)
                name = str(payload.get("patientName", row["patient_name"])).strip()
                normalized, tokens = normalize_name(name)
                if len(tokens) < 2:
                    raise APIError(422, "full_name_required", "Enter the patient's first and last name.")
                profile = patient_profile_values(payload, row)
                conn.execute(
                    "UPDATE patients SET name=?,normalized_name=?,date_of_birth=?,stated_age=?,gender=?,phone=?,email=?,"
                    "address=?,occupation=?,profile_note=?,last_updated=? WHERE id=?",
                    (
                        name, normalized, profile["date_of_birth"], profile["stated_age"], profile["gender"],
                        profile["phone"], profile["email"], profile["address"], profile["occupation"],
                        profile["profile_note"], iso(utc_now()), row["patient_id"],
                    ),
                )
                conn.execute("UPDATE cases SET agent_grafts=?, currency=?, agent_price=?, version=version+1 WHERE id=?",
                             (str(payload["grafts"]), "GBP", str(payload["price"]), case_id))
                self._audit(conn, user["id"], "case.agent_values_updated", "case", case_id, {})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def add_agent_update(
        self,
        case_id: str,
        payload: dict,
        user: sqlite3.Row,
        idempotency_key: str | None = None,
    ) -> dict:
        self._require_role(user, "agent")
        idempotency_key = validate_idempotency_key(idempotency_key)
        fingerprint = request_fingerprint({"caseID": case_id, "payload": payload})
        text = str(payload.get("text", "")).strip()
        if not text:
            raise APIError(422, "empty_update", "Write an update before sending.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                replay = self._idempotency_replay(
                    conn, user["id"], "case.agent_update", idempotency_key, fingerprint
                )
                if replay is not None:
                    replayed = IdempotentReplay(self._case_json(conn, self._case_row(conn, replay)))
                    conn.execute("COMMIT")
                    return replayed
                row = self._case_row(conn, case_id)
                self._assert_owner(row, user)
                if row["status"] == "closed":
                    raise APIError(409, "case_closed", "A closed case cannot be updated.")
                now = iso(utc_now())
                conn.execute("INSERT INTO messages(id,case_id,author_id,author_name,role,created_at,text,approximate_grafts,recommended_price) VALUES (?,?,?,?,?,?,?,?,?)",
                             (str(uuid.uuid4()), case_id, user["id"], user["display_name"], "agent", now, text, None, None))
                conn.execute("UPDATE cases SET status='waiting', version=version+1 WHERE id=?", (case_id,))
                self._audit(conn, user["id"], "case.agent_update_added", "case", case_id, {})
                result = self._case_json(conn, self._case_row(conn, case_id))
                self._store_idempotency_result(
                    conn, user["id"], "case.agent_update", idempotency_key, fingerprint, case_id
                )
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def close_case(self, case_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "agent")
        final_grafts = str(payload.get("finalGrafts", "")).strip()
        final_price = str(payload.get("finalPrice", "")).strip()
        if not final_grafts or not final_price:
            raise APIError(422, "final_plan_required", "Enter the final agreed graft number and price.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = self._case_row(conn, case_id)
                self._assert_owner(row, user)
                if row["status"] != "answered":
                    raise APIError(409, "not_ready_to_close", "Only an answered case can be confirmed and closed.")
                now = iso(utc_now())
                conn.execute(
                    "UPDATE cases SET status='closed',final_grafts=?,final_price=?,finalized_at=?,"
                    "finalized_by=?,version=version+1 WHERE id=?",
                    (final_grafts, final_price, now, user["id"], case_id),
                )
                conn.execute(
                    "INSERT INTO messages(id,case_id,author_id,author_name,role,created_at,text) "
                    "VALUES (?,?,?,?,?,?,?)",
                    (str(uuid.uuid4()), case_id, user["id"], "System", "system", now,
                     f"Final agreed plan confirmed: {final_grafts} grafts · £{final_price.lstrip('£').strip()}"),
                )
                self._audit(conn, user["id"], "case.closed", "case", case_id,
                            {"finalGrafts": final_grafts, "finalPrice": final_price})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def add_photo(
        self,
        case_id: str,
        body: bytes,
        content_type: str,
        user: sqlite3.Row,
        idempotency_key: str | None = None,
    ) -> dict:
        self._require_role(user, "agent")
        idempotency_key = validate_idempotency_key(idempotency_key)
        fingerprint = request_fingerprint({
            "caseID": case_id,
            "contentType": content_type,
            "bodySHA256": hashlib.sha256(body).hexdigest(),
        })
        if not body or len(body) > 20 * 1024 * 1024:
            raise APIError(422, "invalid_photo", "Photo must be between 1 byte and 20 MB.")
        extension = {"image/jpeg": ".jpg", "image/png": ".png", "image/heic": ".heic"}.get(content_type)
        if not extension:
            raise APIError(415, "unsupported_photo", "Use JPEG, PNG or HEIC photos.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                replay = self._idempotency_replay(
                    conn, user["id"], "case.photo_add", idempotency_key, fingerprint
                )
                if replay is not None:
                    replayed = IdempotentReplay(self._case_json(conn, self._case_row(conn, replay)))
                    conn.execute("COMMIT")
                    return replayed
                row = self._case_row(conn, case_id)
                self._assert_owner(row, user)
                photo_id = str(uuid.uuid4())
                case_dir = self.media_root / case_id
                case_dir.mkdir(parents=True, exist_ok=True)
                path = case_dir / f"{photo_id}{extension}"
                path.write_bytes(body)
                now = iso(utc_now())
                relative_path = str(path.relative_to(self.media_root))
                position = conn.execute(
                    "SELECT COALESCE(MAX(position),-1)+1 FROM photos WHERE case_id=?", (case_id,)
                ).fetchone()[0]
                conn.execute("INSERT INTO photos(id,case_id,position,file_path,content_type,uploaded_by,uploaded_at) VALUES (?,?,?,?,?,?,?)",
                             (photo_id, case_id, position, relative_path, content_type, user["id"], now))
                conn.execute(
                    "UPDATE cases SET photo_count=photo_count+1,status='waiting',version=version+1 WHERE id=?",
                    (case_id,),
                )
                self._audit(conn, user["id"], "case.photo_added", "case", case_id, {"photoID": photo_id})
                result = self._case_json(conn, self._case_row(conn, case_id))
                self._store_idempotency_result(
                    conn, user["id"], "case.photo_add", idempotency_key, fingerprint, case_id
                )
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def delete_photo(self, case_id: str, photo_id: str, user: sqlite3.Row) -> dict:
        self._require_role(user, "agent")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                case = self._case_row(conn, case_id)
                self._assert_owner(case, user)
                photo = conn.execute(
                    "SELECT * FROM photos WHERE id=? AND case_id=?",
                    (photo_id, case_id),
                ).fetchone()
                if not photo:
                    raise APIError(404, "photo_not_found", "The photo could not be found.")
                if photo["uploaded_by"] != user["id"]:
                    raise APIError(403, "forbidden", "You can only remove photos uploaded by your account.")
                if not photo["file_path"]:
                    raise APIError(409, "photo_unavailable", "Only uploaded photo files can be removed.")
                if photo["deleted_at"]:
                    raise APIError(409, "photo_already_deleted", "This photo has already been removed.")
                now = iso(utc_now())
                conn.execute(
                    "UPDATE photos SET deleted_at=?,deleted_by=? WHERE id=?",
                    (now, user["id"], photo_id),
                )
                visible_count = conn.execute(
                    "SELECT COUNT(*) FROM photos WHERE case_id=? AND file_path IS NOT NULL AND deleted_at IS NULL",
                    (case_id,),
                ).fetchone()[0]
                conn.execute(
                    "UPDATE cases SET photo_count=?,status='waiting',version=version+1 WHERE id=?",
                    (visible_count, case_id),
                )
                self._audit(conn, user["id"], "case.photo_removed", "photo", photo_id,
                            {"caseID": case_id, "fileRetained": True})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_purge_photo(self, photo_id: str, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                photo = conn.execute("SELECT * FROM photos WHERE id=?", (photo_id,)).fetchone()
                if not photo:
                    raise APIError(404, "photo_not_found", "The photo could not be found.")
                if not photo["deleted_at"]:
                    raise APIError(409, "photo_not_deleted", "Only previously removed photos can be permanently deleted.")

                file_path = None
                if photo["file_path"]:
                    media_root = self.media_root.resolve()
                    candidate = (media_root / photo["file_path"]).resolve()
                    if media_root not in candidate.parents:
                        raise APIError(409, "invalid_photo_path", "The stored photo path is invalid.")
                    file_path = candidate

                conn.execute("DELETE FROM photos WHERE id=?", (photo_id,))
                self._audit(conn, user["id"], "case.photo_purged", "photo", photo_id,
                            {"caseID": photo["case_id"], "softDeletedAt": photo["deleted_at"]})
                conn.execute("COMMIT")
                if file_path and file_path.is_file():
                    try:
                        file_path.unlink()
                    except OSError:
                        pass
                return {"id": photo_id, "purged": True}
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_delete_case(self, case_id: str, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        case_directory = None
        patient_profile_path = None
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                case = self._case_row(conn, case_id)
                patient = conn.execute(
                    "SELECT * FROM patients WHERE id=?", (case["patient_id"],)
                ).fetchone()
                photo_count = conn.execute(
                    "SELECT COUNT(*) FROM photos WHERE case_id=?", (case_id,)
                ).fetchone()[0]
                message_count = conn.execute(
                    "SELECT COUNT(*) FROM messages WHERE case_id=?", (case_id,)
                ).fetchone()[0]

                media_root = self.media_root.resolve()
                candidate_directory = (media_root / case_id).resolve()
                if media_root not in candidate_directory.parents:
                    raise APIError(409, "invalid_case_path", "The stored case media path is invalid.")
                case_directory = candidate_directory

                conn.execute("DELETE FROM cases WHERE id=?", (case_id,))
                remaining_cases = conn.execute(
                    "SELECT COUNT(*) FROM cases WHERE patient_id=?", (case["patient_id"],)
                ).fetchone()[0]
                patient_deleted = remaining_cases == 0
                if patient_deleted:
                    if patient and patient["profile_photo_path"]:
                        candidate = (media_root / patient["profile_photo_path"]).resolve()
                        if media_root not in candidate.parents:
                            raise APIError(409, "invalid_patient_photo_path", "The stored patient photo path is invalid.")
                        patient_profile_path = candidate
                    conn.execute("DELETE FROM patients WHERE id=?", (case["patient_id"],))

                self._audit(
                    conn,
                    user["id"],
                    "case.deleted",
                    "case",
                    case_id,
                    {
                        "reference": case["reference"],
                        "patientID": case["patient_id"],
                        "patientDeleted": patient_deleted,
                        "photoCount": photo_count,
                        "messageCount": message_count,
                    },
                )
                conn.execute("COMMIT")
            except Exception:
                conn.execute("ROLLBACK")
                raise

        if case_directory and case_directory.is_dir():
            try:
                shutil.rmtree(case_directory)
            except OSError:
                pass
        if patient_profile_path and patient_profile_path.is_file():
            try:
                patient_profile_path.unlink()
            except OSError:
                pass
        return {
            "id": case_id,
            "reference": case["reference"],
            "deleted": True,
            "patientDeleted": patient_deleted,
            "photoCount": photo_count,
            "messageCount": message_count,
        }

    def get_photo(self, photo_id: str, user: sqlite3.Row) -> tuple[bytes, str]:
        with self.connect() as conn:
            photo = conn.execute(
                "SELECT p.*,c.agent_id,c.assigned_doctor_id,u.agency_id case_agency_id FROM photos p "
                "JOIN cases c ON c.id=p.case_id JOIN users u ON u.id=c.agent_id WHERE p.id=?",
                (photo_id,),
            ).fetchone()
            if not photo:
                raise APIError(404, "photo_not_found", "The photo could not be found.")
            self._assert_case_visible(photo, user)
            if photo["deleted_at"] and user["role"] not in {"admin", "manager"}:
                raise APIError(404, "photo_not_found", "The photo could not be found.")
            if not photo["file_path"] or not photo["content_type"]:
                raise APIError(404, "photo_unavailable", "This case does not have an uploaded photo file.")
            media_root = self.media_root.resolve()
            file_path = (media_root / photo["file_path"]).resolve()
            if media_root not in file_path.parents or not file_path.is_file():
                raise APIError(404, "photo_unavailable", "The uploaded photo file is unavailable.")
            return file_path.read_bytes(), photo["content_type"]

    def add_message_photo(
        self, case_id: str, body: bytes, content_type: str, message_text: str, user: sqlite3.Row
    ) -> dict:
        self._require_any_role(user, "agent", "doctor", "admin")
        if not body or len(body) > 20 * 1024 * 1024:
            raise APIError(422, "invalid_photo", "Photo must be between 1 byte and 20 MB.")
        extension = {"image/jpeg": ".jpg", "image/png": ".png", "image/heic": ".heic"}.get(content_type)
        if not extension:
            raise APIError(415, "unsupported_photo", "Use JPEG, PNG or HEIC photos.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                case = self._case_row(conn, case_id)
                self._assert_case_visible(case, user)
                if user["role"] == "agent":
                    self._assert_owner(case, user)
                if user["role"] == "doctor" and case["assigned_doctor_id"] not in (None, user["id"]):
                    raise APIError(409, "case_changed", "This case is assigned to another doctor.")
                if case["status"] == "closed":
                    raise APIError(409, "case_closed", "A closed case cannot receive new messages.")

                message_id = str(uuid.uuid4())
                message_dir = self.media_root / case_id / "messages"
                message_dir.mkdir(parents=True, exist_ok=True)
                path = message_dir / f"{message_id}{extension}"
                path.write_bytes(body)
                relative_path = str(path.relative_to(self.media_root))
                now = iso(utc_now())
                conn.execute(
                    "INSERT INTO messages(id,case_id,author_id,author_name,role,created_at,text,"
                    "approximate_grafts,recommended_price,attachment_path,attachment_content_type) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    (message_id, case_id, user["id"], user["display_name"], user["role"], now,
                     message_text, None, None, relative_path, content_type),
                )
                if user["role"] == "doctor" and case["assigned_doctor_id"] is None:
                    conn.execute("UPDATE cases SET assigned_doctor_id=? WHERE id=?", (user["id"], case_id))
                    conn.execute(
                        "UPDATE patients SET assigned_doctor_id=?,last_updated=? WHERE id=?",
                        (user["id"], now, case["patient_id"]),
                    )
                if user["role"] == "agent":
                    conn.execute("UPDATE cases SET status='waiting',version=version+1 WHERE id=?", (case_id,))
                elif user["role"] == "doctor":
                    conn.execute("UPDATE cases SET status='answered',version=version+1 WHERE id=?", (case_id,))
                else:
                    conn.execute("UPDATE cases SET version=version+1 WHERE id=?", (case_id,))
                self._audit(conn, user["id"], "case.annotated_photo_added", "message", message_id,
                            {"caseID": case_id, "originalRetained": True})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def delete_message(self, case_id: str, message_id: str, user: sqlite3.Row) -> dict:
        self._require_any_role(user, "agent", "doctor")
        message_id = message_id.lower()
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                case = self._case_row(conn, case_id)
                self._assert_case_visible(case, user)
                if user["role"] == "agent":
                    self._assert_owner(case, user)
                message = conn.execute(
                    "SELECT * FROM messages WHERE id=? AND case_id=?",
                    (message_id, case_id),
                ).fetchone()
                if not message:
                    raise APIError(404, "message_not_found", "The message could not be found.")
                if message["author_id"] != user["id"]:
                    raise APIError(403, "forbidden", "You can only remove messages written by your account.")
                if message["role"] not in {"agent", "doctor"}:
                    raise APIError(403, "forbidden", "This message cannot be removed.")

                if not message["deleted_at"]:
                    now = iso(utc_now())
                    conn.execute(
                        "UPDATE messages SET deleted_at=?,deleted_by=? WHERE id=?",
                        (now, user["id"], message_id),
                    )
                    latest_active_message = conn.execute(
                        "SELECT role FROM messages WHERE case_id=? AND role IN ('agent','doctor') "
                        "AND deleted_at IS NULL ORDER BY created_at DESC,rowid DESC LIMIT 1",
                        (case_id,),
                    ).fetchone()
                    if case["status"] == "closed":
                        conn.execute(
                            "UPDATE cases SET version=version+1 WHERE id=?",
                            (case_id,),
                        )
                    else:
                        next_status = (
                            "answered"
                            if latest_active_message and latest_active_message["role"] == "doctor"
                            else "waiting"
                        )
                        conn.execute(
                            "UPDATE cases SET status=?,version=version+1 WHERE id=?",
                            (next_status, case_id),
                        )
                    self._audit(conn, user["id"], "case.message_removed", "message", message_id,
                                {"caseID": case_id, "contentRetained": True})

                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def get_message_photo(self, message_id: str, user: sqlite3.Row) -> tuple[bytes, str]:
        with self.connect() as conn:
            message = conn.execute(
                "SELECT m.attachment_path,m.attachment_content_type,m.deleted_at,c.agent_id,c.assigned_doctor_id,"
                "u.agency_id case_agency_id FROM messages m JOIN cases c ON c.id=m.case_id "
                "JOIN users u ON u.id=c.agent_id WHERE m.id=?",
                (message_id,),
            ).fetchone()
            if not message or not message["attachment_path"] or not message["attachment_content_type"]:
                raise APIError(404, "message_photo_not_found", "The message photo could not be found.")
            self._assert_case_visible(message, user)
            if message["deleted_at"] and user["role"] not in {"admin", "manager"}:
                raise APIError(404, "message_photo_not_found", "The message photo could not be found.")
            media_root = self.media_root.resolve()
            file_path = (media_root / message["attachment_path"]).resolve()
            if media_root not in file_path.parents or not file_path.is_file():
                raise APIError(404, "message_photo_unavailable", "The message photo file is unavailable.")
            return file_path.read_bytes(), message["attachment_content_type"]

    def admin_users(self, user: sqlite3.Row) -> list[dict]:
        self._require_any_role(user, "admin", "manager")
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT u.*, ag.name agency_name, "
                "(SELECT COUNT(*) FROM cases c WHERE c.agent_id=u.id) agent_case_count, "
                "(SELECT COUNT(*) FROM patients p WHERE p.assigned_doctor_id=u.id) doctor_patient_count "
                "FROM users u LEFT JOIN agencies ag ON ag.id=u.agency_id "
                "WHERE NOT EXISTS (SELECT 1 FROM agency_mcp_credentials mc WHERE mc.service_user_id=u.id) "
                "ORDER BY u.active DESC, u.role, u.display_name"
            ).fetchall()
            return [{
                **self._public_user(row),
                "agencyName": row["agency_name"],
                "active": bool(row["active"]),
                "createdAt": row["created_at"],
                "caseCount": row["agent_case_count"] if row["role"] == "agent" else 0,
                "patientCount": row["doctor_patient_count"] if row["role"] == "doctor" else 0,
            } for row in rows]

    def admin_create_user(self, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        username = str(payload.get("username", "")).strip()
        display_name = str(payload.get("displayName", "")).strip()
        role = str(payload.get("role", "")).strip().lower()
        password = str(payload.get("password", ""))
        if not display_name or role not in {"doctor", "agent", "admin", "manager"}:
            raise APIError(422, "invalid_user", "Display name and a valid role are required.")
        if len(password) < 10:
            raise APIError(422, "weak_password", "The temporary password must contain at least 10 characters.")
        if username and any(ch.isspace() for ch in username):
            raise APIError(422, "invalid_username", "Username cannot contain spaces.")
        agency_id = str(payload.get("agencyID", "")).strip() or None
        user_id = f"{role}-{uuid.uuid4().hex[:12]}"
        salt, digest = hash_password(password)
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                if not username:
                    base = username_base(display_name)
                    if not base:
                        raise APIError(422, "invalid_username", "A username could not be generated from this display name.")
                    username = base
                    suffix = 2
                    while conn.execute("SELECT 1 FROM users WHERE username=?", (username,)).fetchone():
                        username = f"{base}{suffix}"
                        suffix += 1
                if role == "agent":
                    agency = conn.execute("SELECT * FROM agencies WHERE id=? AND active=1", (agency_id,)).fetchone()
                    if not agency:
                        raise APIError(422, "agency_required", "Select an active agency for the agent.")
                else:
                    agency_id = None
                conn.execute(
                    "INSERT INTO users(id,username,display_name,role,password_salt,password_hash,agency_id,active,created_at) VALUES (?,?,?,?,?,?,?,1,?)",
                    (user_id, username, display_name, role, salt, digest, agency_id, iso(utc_now())),
                )
                self._audit(conn, user["id"], "user.created", "user", user_id,
                            {"username": username, "role": role, "agencyID": agency_id})
                row = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
                conn.execute("COMMIT")
                agency_name = conn.execute("SELECT name FROM agencies WHERE id=?", (agency_id,)).fetchone() if agency_id else None
                return {**self._public_user(row), "agencyName": agency_name[0] if agency_name else None,
                        "active": True, "createdAt": row["created_at"],
                        "caseCount": 0, "patientCount": 0}
            except sqlite3.IntegrityError:
                conn.execute("ROLLBACK")
                raise APIError(409, "username_exists", "This username is already in use.")
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_update_user(self, user_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                target = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
                if not target:
                    raise APIError(404, "user_not_found", "The user could not be found.")
                if conn.execute(
                    "SELECT 1 FROM agency_mcp_credentials WHERE service_user_id=?", (user_id,)
                ).fetchone():
                    raise APIError(409, "managed_service_account", "This MCP service account is managed from its agency settings.")
                username = str(payload.get("username", target["username"])).strip()
                display_name = str(payload.get("displayName", target["display_name"])).strip()
                role = str(payload.get("role", target["role"])).strip().lower()
                agency_id = str(payload.get("agencyID", target["agency_id"] or "")).strip() or None
                new_password = str(payload.get("password", ""))
                if not username or any(ch.isspace() for ch in username):
                    raise APIError(422, "invalid_username", "Enter a username without spaces.")
                if len(display_name) < 2 or len(display_name) > 120:
                    raise APIError(422, "invalid_display_name", "Enter a valid display name.")
                if role not in {"doctor", "agent", "admin", "manager"}:
                    raise APIError(422, "invalid_user", "Select a valid role.")
                if user_id == user["id"] and role != "admin":
                    raise APIError(409, "cannot_change_own_role", "You cannot remove your own admin role.")
                if role != target["role"]:
                    history_count = sum((
                        conn.execute("SELECT COUNT(*) FROM cases WHERE agent_id=?", (user_id,)).fetchone()[0],
                        conn.execute("SELECT COUNT(*) FROM patients WHERE assigned_doctor_id=?", (user_id,)).fetchone()[0],
                        conn.execute("SELECT COUNT(*) FROM messages WHERE author_id=?", (user_id,)).fetchone()[0],
                        conn.execute("SELECT COUNT(*) FROM photos WHERE uploaded_by=?", (user_id,)).fetchone()[0],
                    ))
                    if history_count:
                        raise APIError(409, "role_change_has_history",
                                       "This user's role cannot be changed because consultation history is attached to the account.")
                if role == "agent":
                    agency = conn.execute("SELECT * FROM agencies WHERE id=? AND active=1", (agency_id,)).fetchone()
                    if not agency:
                        raise APIError(422, "agency_required", "Select an active agency for the agent.")
                else:
                    agency_id = None
                if new_password and len(new_password) < 10:
                    raise APIError(422, "weak_password", "The new temporary password must contain at least 10 characters.")
                conn.execute(
                    "UPDATE users SET username=?,display_name=?,role=?,agency_id=? WHERE id=?",
                    (username, display_name, role, agency_id, user_id),
                )
                if new_password:
                    salt, digest = hash_password(new_password)
                    conn.execute("UPDATE users SET password_salt=?,password_hash=? WHERE id=?", (salt, digest, user_id))
                    conn.execute("DELETE FROM sessions WHERE user_id=?", (user_id,))
                self._audit(conn, user["id"], "user.updated", "user", user_id,
                            {"username": username, "displayName": display_name, "role": role,
                             "agencyID": agency_id, "passwordChanged": bool(new_password)})
                updated = conn.execute(
                    "SELECT u.*,ag.name agency_name,"
                    "(SELECT COUNT(*) FROM cases c WHERE c.agent_id=u.id) agent_case_count,"
                    "(SELECT COUNT(*) FROM patients p WHERE p.assigned_doctor_id=u.id) doctor_patient_count "
                    "FROM users u LEFT JOIN agencies ag ON ag.id=u.agency_id WHERE u.id=?",
                    (user_id,),
                ).fetchone()
                conn.execute("COMMIT")
                return {
                    **self._public_user(updated), "agencyName": updated["agency_name"],
                    "active": bool(updated["active"]), "createdAt": updated["created_at"],
                    "caseCount": updated["agent_case_count"] if role == "agent" else 0,
                    "patientCount": updated["doctor_patient_count"] if role == "doctor" else 0,
                }
            except sqlite3.IntegrityError:
                conn.execute("ROLLBACK")
                raise APIError(409, "username_exists", "This username is already in use.")
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_set_user_active(self, user_id: str, active: bool, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        if user_id == user["id"] and not active:
            raise APIError(409, "cannot_disable_self", "You cannot deactivate your own admin account.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                target = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
                if not target:
                    raise APIError(404, "user_not_found", "The user could not be found.")
                if conn.execute(
                    "SELECT 1 FROM agency_mcp_credentials WHERE service_user_id=?", (user_id,)
                ).fetchone():
                    raise APIError(409, "managed_service_account", "This MCP service account is managed from its agency settings.")
                conn.execute("UPDATE users SET active=? WHERE id=?", (1 if active else 0, user_id))
                if not active:
                    conn.execute("DELETE FROM sessions WHERE user_id=?", (user_id,))
                self._audit(conn, user["id"], "user.activated" if active else "user.deactivated", "user", user_id, {})
                conn.execute("COMMIT")
                return {"id": user_id, "active": active}
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_delete_user(self, user_id: str, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        if user_id == user["id"]:
            raise APIError(409, "cannot_delete_self", "You cannot delete your own admin account.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                target = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
                if not target:
                    raise APIError(404, "user_not_found", "The user could not be found.")
                if conn.execute(
                    "SELECT 1 FROM agency_mcp_credentials WHERE service_user_id=?", (user_id,)
                ).fetchone():
                    raise APIError(409, "managed_service_account", "This MCP service account cannot be deleted directly.")
                if target["active"]:
                    raise APIError(409, "deactivate_first", "Deactivate the user before deleting the account.")
                counts = {
                    "cases": conn.execute("SELECT COUNT(*) FROM cases WHERE agent_id=?", (user_id,)).fetchone()[0],
                    "patients": conn.execute("SELECT COUNT(*) FROM patients WHERE assigned_doctor_id=?", (user_id,)).fetchone()[0],
                    "messages": conn.execute("SELECT COUNT(*) FROM messages WHERE author_id=?", (user_id,)).fetchone()[0],
                    "photos": conn.execute("SELECT COUNT(*) FROM photos WHERE uploaded_by=?", (user_id,)).fetchone()[0],
                }
                if any(counts.values()):
                    raise APIError(409, "user_has_history",
                                   "This user has consultation history and cannot be deleted. Keep the account deactivated.", counts)
                conn.execute("DELETE FROM sessions WHERE user_id=?", (user_id,))
                conn.execute("DELETE FROM users WHERE id=?", (user_id,))
                self._audit(conn, user["id"], "user.deleted", "user", user_id,
                            {"username": target["username"], "role": target["role"], "agencyID": target["agency_id"]})
                conn.execute("COMMIT")
                return {"id": user_id, "deleted": True}
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_agencies(self, user: sqlite3.Row) -> list[dict]:
        self._require_any_role(user, "admin", "manager")
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT ag.*, (SELECT COUNT(*) FROM users u WHERE u.agency_id=ag.id AND NOT EXISTS "
                "(SELECT 1 FROM agency_mcp_credentials mc WHERE mc.service_user_id=u.id)) user_count, "
                "mc.rotated_at mcp_rotated_at "
                "FROM agencies ag LEFT JOIN agency_mcp_credentials mc ON mc.agency_id=ag.id "
                "ORDER BY ag.active DESC, ag.name"
            ).fetchall()
            return [{"id": row["id"], "name": row["name"], "active": bool(row["active"]),
                     "userCount": row["user_count"], "mcpConfigured": bool(row["mcp_rotated_at"]),
                     "mcpRotatedAt": row["mcp_rotated_at"]} for row in rows]

    def admin_create_agency(self, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        name = str(payload.get("name", "")).strip()
        if len(name) < 2:
            raise APIError(422, "invalid_agency", "Enter an agency name.")
        agency_id = "agency-" + uuid.uuid4().hex[:12]
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                conn.execute("INSERT INTO agencies VALUES (?,?,1,?)", (agency_id, name, iso(utc_now())))
                self._audit(conn, user["id"], "agency.created", "agency", agency_id, {"name": name})
                conn.execute("COMMIT")
                return {"id": agency_id, "name": name, "active": True, "userCount": 0,
                        "mcpConfigured": False, "mcpRotatedAt": None}
            except sqlite3.IntegrityError:
                conn.execute("ROLLBACK")
                raise APIError(409, "agency_exists", "An agency with this name already exists.")
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_update_agency(self, agency_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        name = str(payload.get("name", "")).strip()
        if len(name) < 2:
            raise APIError(422, "invalid_agency", "Enter a valid agency name.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                agency = conn.execute("SELECT * FROM agencies WHERE id=?", (agency_id,)).fetchone()
                if not agency:
                    raise APIError(404, "agency_not_found", "The agency could not be found.")
                conn.execute("UPDATE agencies SET name=? WHERE id=?", (name, agency_id))
                self._audit(conn, user["id"], "agency.updated", "agency", agency_id,
                            {"from": agency["name"], "to": name})
                user_count = conn.execute(
                    "SELECT COUNT(*) FROM users u WHERE u.agency_id=? AND NOT EXISTS "
                    "(SELECT 1 FROM agency_mcp_credentials mc WHERE mc.service_user_id=u.id)",
                    (agency_id,),
                ).fetchone()[0]
                conn.execute("COMMIT")
                credential = conn.execute(
                    "SELECT rotated_at FROM agency_mcp_credentials WHERE agency_id=?", (agency_id,)
                ).fetchone()
                return {"id": agency_id, "name": name, "active": bool(agency["active"]),
                        "userCount": user_count, "mcpConfigured": bool(credential),
                        "mcpRotatedAt": credential["rotated_at"] if credential else None}
            except sqlite3.IntegrityError:
                conn.execute("ROLLBACK")
                raise APIError(409, "agency_exists", "An agency with this name already exists.")
            except Exception:
                conn.execute("ROLLBACK")
                raise

    @staticmethod
    def _mcp_connection_json(agency: sqlite3.Row, credential: sqlite3.Row | None) -> dict:
        return {
            "agencyID": agency["id"],
            "agencyName": agency["name"],
            "endpointURL": public_mcp_url(),
            "configured": credential is not None,
            "rotatedAt": credential["rotated_at"] if credential else None,
        }

    def admin_mcp_connection(self, agency_id: str, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        with self.connect() as conn:
            agency = conn.execute("SELECT * FROM agencies WHERE id=?", (agency_id,)).fetchone()
            if not agency:
                raise APIError(404, "agency_not_found", "The agency could not be found.")
            credential = conn.execute(
                "SELECT * FROM agency_mcp_credentials WHERE agency_id=?", (agency_id,)
            ).fetchone()
            return self._mcp_connection_json(agency, credential)

    def admin_rotate_mcp_token(self, agency_id: str, user: sqlite3.Row) -> dict:
        """Create or replace an agency token; plaintext exists only in this response."""
        self._require_role(user, "admin")
        plaintext = "cfmcp_" + secrets.token_urlsafe(48)
        digest = mcp_token_hash(plaintext)
        now = iso(utc_now())
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                agency = conn.execute("SELECT * FROM agencies WHERE id=?", (agency_id,)).fetchone()
                if not agency:
                    raise APIError(404, "agency_not_found", "The agency could not be found.")
                if not agency["active"]:
                    raise APIError(409, "agency_inactive", "Activate the agency before generating an MCP token.")
                credential = conn.execute(
                    "SELECT * FROM agency_mcp_credentials WHERE agency_id=?", (agency_id,)
                ).fetchone()
                service_user = None
                if credential:
                    service_user = conn.execute(
                        "SELECT * FROM users WHERE id=?", (credential["service_user_id"],)
                    ).fetchone()
                if not service_user:
                    service_user_id = "agent-mcp-" + uuid.uuid4().hex[:12]
                    base = f"mcp.{username_base(agency['name']) or 'agency'}"
                    username = base
                    suffix = 2
                    while conn.execute("SELECT 1 FROM users WHERE username=?", (username,)).fetchone():
                        username = f"{base}{suffix}"
                        suffix += 1
                    salt, password_digest = hash_password(secrets.token_urlsafe(48))
                    conn.execute(
                        "INSERT INTO users(id,username,display_name,role,password_salt,password_hash,agency_id,active,created_at) "
                        "VALUES (?,?,?,'agent',?,?,?,1,?)",
                        (service_user_id, username, f"{agency['name']} MCP Integration", salt,
                         password_digest, agency_id, now),
                    )
                else:
                    service_user_id = service_user["id"]
                    conn.execute(
                        "UPDATE users SET display_name=?,agency_id=?,role='agent',active=1 WHERE id=?",
                        (f"{agency['name']} MCP Integration", agency_id, service_user_id),
                    )
                conn.execute(
                    "INSERT INTO agency_mcp_credentials(agency_id,token_hash,service_user_id,created_at,rotated_at,rotated_by) "
                    "VALUES (?,?,?,?,?,?) ON CONFLICT(agency_id) DO UPDATE SET "
                    "token_hash=excluded.token_hash,service_user_id=excluded.service_user_id,"
                    "rotated_at=excluded.rotated_at,rotated_by=excluded.rotated_by",
                    (agency_id, digest, service_user_id,
                     credential["created_at"] if credential else now, now, user["id"]),
                )
                self._audit(conn, user["id"], "agency.mcp_token_rotated", "agency", agency_id,
                            {"serviceUserID": service_user_id})
                updated = conn.execute(
                    "SELECT * FROM agency_mcp_credentials WHERE agency_id=?", (agency_id,)
                ).fetchone()
                conn.execute("COMMIT")
                return {**self._mcp_connection_json(agency, updated), "accessToken": plaintext}
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def authenticate_mcp_token(self, token: str) -> dict:
        if not token.startswith("cfmcp_") or len(token) < 48:
            raise APIError(401, "invalid_mcp_token", "The MCP access token is invalid.")
        digest = mcp_token_hash(token)
        with self.connect() as conn:
            row = conn.execute(
                "SELECT mc.agency_id,mc.service_user_id,mc.rotated_at,ag.name agency_name,"
                "ag.active agency_active,u.active user_active,u.role "
                "FROM agency_mcp_credentials mc JOIN agencies ag ON ag.id=mc.agency_id "
                "JOIN users u ON u.id=mc.service_user_id WHERE mc.token_hash=?",
                (digest,),
            ).fetchone()
            if not row or not row["agency_active"] or not row["user_active"] or row["role"] != "agent":
                raise APIError(401, "invalid_mcp_token", "The MCP access token is invalid.")
            return {
                "agencyID": row["agency_id"], "agencyName": row["agency_name"],
                "serviceUserID": row["service_user_id"], "rotatedAt": row["rotated_at"],
            }

    def mcp_service_user(self, service_user_id: str, agency_id: str) -> sqlite3.Row:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT u.* FROM users u JOIN agency_mcp_credentials mc ON mc.service_user_id=u.id "
                "JOIN agencies ag ON ag.id=mc.agency_id WHERE u.id=? AND mc.agency_id=? "
                "AND u.active=1 AND ag.active=1 AND u.role='agent'",
                (service_user_id, agency_id),
            ).fetchone()
            if not row:
                raise APIError(401, "invalid_mcp_principal", "The MCP agency principal is no longer active.")
            return row

    def admin_cases(self, user: sqlite3.Row) -> list[dict]:
        self._require_any_role(user, "admin", "manager")
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT c.id,c.reference,c.uploaded_at,c.status,c.photo_count,c.agent_note,c.agent_grafts,c.currency,c.agent_price,"
                "c.final_grafts,c.final_price,c.finalized_at,"
                "p.id patient_id,p.name patient_name,p.assigned_doctor_id,p.date_of_birth,p.stated_age,p.gender,p.phone,p.email,"
                "p.address,p.occupation,p.profile_note,"
                "a.display_name agent_name,ag.name agency_name,d.display_name doctor_name,"
                "(SELECT COUNT(*) FROM messages m WHERE m.case_id=c.id AND m.deleted_at IS NULL) message_count,"
                "(SELECT COUNT(*) FROM messages m WHERE m.case_id=c.id AND m.deleted_at IS NOT NULL) deleted_message_count "
                "FROM cases c JOIN patients p ON p.id=c.patient_id "
                "JOIN users a ON a.id=c.agent_id LEFT JOIN agencies ag ON ag.id=a.agency_id "
                "LEFT JOIN users d ON d.id=p.assigned_doctor_id "
                "ORDER BY c.uploaded_at DESC"
            ).fetchall()
            result = []
            for row in rows:
                photos = conn.execute(
                    "SELECT p.id,p.position,p.file_path,p.uploaded_at,p.deleted_at,u.display_name deleted_by_name "
                    "FROM photos p LEFT JOIN users u ON u.id=p.deleted_by "
                    "WHERE p.case_id=? AND p.file_path IS NOT NULL ORDER BY p.position",
                    (row["id"],),
                ).fetchall()
                messages = conn.execute(
                    "SELECT m.*,u.display_name deleted_by_name FROM messages m "
                    "LEFT JOIN users u ON u.id=m.deleted_by WHERE m.case_id=? ORDER BY m.created_at,m.rowid",
                    (row["id"],),
                ).fetchall()
                latest_message = conn.execute(
                    "SELECT author_name,text,created_at,attachment_path FROM messages "
                    "WHERE case_id=? AND role <> 'system' AND deleted_at IS NULL "
                    "ORDER BY created_at DESC,rowid DESC LIMIT 1",
                    (row["id"],),
                ).fetchone()
                result.append({
                    "id": row["id"], "reference": row["reference"], "patientID": row["patient_id"],
                    "patientName": row["patient_name"], "agentName": row["agent_name"],
                    "dateOfBirth": row["date_of_birth"], "statedAge": row["stated_age"],
                    "age": patient_age(row["date_of_birth"], row["stated_age"]),
                    "gender": row["gender"], "patientPhone": row["phone"], "patientEmail": row["email"],
                    "patientAddress": row["address"], "occupation": row["occupation"],
                    "profileNote": row["profile_note"],
                    "agencyName": row["agency_name"],
                    "doctorID": row["assigned_doctor_id"], "doctorName": row["doctor_name"],
                    "uploadedAt": row["uploaded_at"], "status": row["status"],
                    "agentNote": row["agent_note"],
                    "photoCount": len(photos),
                    "deletedPhotoCount": sum(1 for photo in photos if photo["deleted_at"]),
                    "photos": [{
                        "id": photo["id"], "position": photo["position"],
                        "available": bool(photo["file_path"]), "deleted": bool(photo["deleted_at"]),
                        "deletedAt": photo["deleted_at"], "deletedByName": photo["deleted_by_name"],
                    } for photo in photos],
                    "messages": [{
                        "id": message["id"], "author": message["author_name"], "role": message["role"],
                        "createdAt": message["created_at"], "text": message["text"],
                        "approximateGrafts": message["approximate_grafts"],
                        "recommendedPrice": message["recommended_price"],
                        "attachmentPhotoID": message["id"] if message["attachment_path"] else None,
                        "deletedAt": message["deleted_at"], "deletedByName": message["deleted_by_name"],
                    } for message in messages],
                    "messageCount": row["message_count"],
                    "deletedMessageCount": row["deleted_message_count"],
                    "latestMessageAuthor": latest_message["author_name"] if latest_message else None,
                    "latestMessageText": latest_message["text"] if latest_message else None,
                    "latestMessageAt": latest_message["created_at"] if latest_message else None,
                    "latestMessageHasPhoto": bool(latest_message["attachment_path"]) if latest_message else False,
                    "grafts": row["agent_grafts"], "currency": row["currency"], "price": row["agent_price"],
                    "finalGrafts": row["final_grafts"], "finalPrice": row["final_price"],
                    "finalizedAt": row["finalized_at"],
                })
            return result

    def admin_assign_doctor(self, patient_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "admin")
        doctor_id = payload.get("doctorID") or None
        reason = str(payload.get("reason", "")).strip()
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                patient = conn.execute("SELECT * FROM patients WHERE id=?", (patient_id,)).fetchone()
                if not patient:
                    raise APIError(404, "patient_not_found", "The patient could not be found.")
                if doctor_id:
                    doctor = conn.execute("SELECT * FROM users WHERE id=? AND role='doctor' AND active=1", (doctor_id,)).fetchone()
                    if not doctor:
                        raise APIError(422, "invalid_doctor", "Select an active doctor.")
                previous = patient["assigned_doctor_id"]
                if previous and previous != doctor_id and not reason:
                    raise APIError(422, "reason_required", "Enter a reason when changing the assigned doctor.")
                now = iso(utc_now())
                conn.execute("UPDATE patients SET assigned_doctor_id=?, last_updated=? WHERE id=?", (doctor_id, now, patient_id))
                conn.execute("UPDATE cases SET assigned_doctor_id=?, version=version+1 WHERE patient_id=? AND status!='closed'",
                             (doctor_id, patient_id))
                self._audit(conn, user["id"], "patient.doctor_assigned", "patient", patient_id,
                            {"from": previous, "to": doctor_id, "reason": reason})
                conn.execute("COMMIT")
                return {"patientID": patient_id, "doctorID": doctor_id}
            except Exception:
                conn.execute("ROLLBACK")
                raise

    @staticmethod
    def _next_reference(conn: sqlite3.Connection, counter: str, prefix: str) -> str:
        conn.execute("UPDATE counters SET value=value+1 WHERE name=?", (counter,))
        value = conn.execute("SELECT value FROM counters WHERE name=?", (counter,)).fetchone()[0]
        return f"{prefix}{value}"

    @staticmethod
    def _require_role(user: sqlite3.Row, role: str) -> None:
        if user["role"] != role:
            raise APIError(403, "forbidden", f"This action requires the {role} role.")

    @staticmethod
    def _require_any_role(user: sqlite3.Row, *roles: str) -> None:
        if user["role"] not in roles:
            raise APIError(403, "forbidden", "This account does not have access to this record.")

    @staticmethod
    def _assert_owner(case: sqlite3.Row, user: sqlite3.Row) -> None:
        if case["agent_id"] != user["id"]:
            raise APIError(403, "forbidden", "You cannot change another agent's case.")

    @staticmethod
    def _assert_case_visible(case: sqlite3.Row, user: sqlite3.Row) -> None:
        if user["role"] != "agent" or case["agent_id"] == user["id"]:
            return
        if user["agency_id"] and case["case_agency_id"] == user["agency_id"]:
            return
        raise APIError(403, "forbidden", "This case belongs to another agency.")

    @staticmethod
    def _idempotency_replay(
        conn: sqlite3.Connection,
        actor_id: str,
        operation: str,
        idempotency_key: str | None,
        request_hash: str,
    ) -> str | None:
        if idempotency_key is None:
            return None
        record = conn.execute(
            "SELECT request_hash,entity_id FROM idempotency_records "
            "WHERE actor_id=? AND operation=? AND idempotency_key=?",
            (actor_id, operation, idempotency_key),
        ).fetchone()
        if not record:
            return None
        if not hmac.compare_digest(record["request_hash"], request_hash):
            raise APIError(
                409,
                "idempotency_conflict",
                "This Idempotency-Key was already used with different request data.",
            )
        return str(record["entity_id"])

    @staticmethod
    def _store_idempotency_result(
        conn: sqlite3.Connection,
        actor_id: str,
        operation: str,
        idempotency_key: str | None,
        request_hash: str,
        entity_id: str,
    ) -> None:
        if idempotency_key is None:
            return
        conn.execute(
            "INSERT INTO idempotency_records("
            "actor_id,operation,idempotency_key,request_hash,entity_id,created_at"
            ") VALUES (?,?,?,?,?,?)",
            (
                actor_id,
                operation,
                idempotency_key,
                request_hash,
                entity_id,
                iso(utc_now()),
            ),
        )

    @staticmethod
    def _audit(conn: sqlite3.Connection, actor: str, action: str, entity_type: str, entity_id: str, detail: dict) -> None:
        conn.execute("INSERT INTO audit_events(actor_id,action,entity_type,entity_id,detail_json,created_at) VALUES (?,?,?,?,?,?)",
                     (actor, action, entity_type, entity_id, json.dumps(detail, separators=(",", ":")), iso(utc_now())))

    @staticmethod
    def _case_row(conn: sqlite3.Connection, case_id: str) -> sqlite3.Row:
        row = conn.execute(
            "SELECT c.*, p.name patient_name, p.assigned_doctor_id patient_doctor, p.last_updated, "
            "p.date_of_birth,p.stated_age,p.gender,p.phone,p.email,p.address,p.occupation,p.profile_note, "
            "u.display_name agent_name, u.agency_id case_agency_id, a.name agency_name "
            "FROM cases c JOIN patients p ON p.id=c.patient_id "
            "JOIN users u ON u.id=c.agent_id LEFT JOIN agencies a ON a.id=u.agency_id WHERE c.id=?", (case_id,),
        ).fetchone()
        if not row:
            raise APIError(404, "case_not_found", "The case could not be found.")
        return row

    @staticmethod
    def _case_json(conn: sqlite3.Connection, row: sqlite3.Row) -> dict:
        messages = conn.execute(
            "SELECT * FROM messages WHERE case_id=? AND deleted_at IS NULL ORDER BY created_at,rowid",
            (row["id"],),
        ).fetchall()
        photos = conn.execute(
            "SELECT id,position FROM photos WHERE case_id=? AND file_path IS NOT NULL "
            "AND deleted_at IS NULL ORDER BY position",
            (row["id"],),
        ).fetchall()
        return {
            "id": row["id"], "reference": row["reference"],
            "patient": {"id": row["patient_id"], "name": row["patient_name"],
                        "assignedDoctorID": row["patient_doctor"], "lastUpdated": row["last_updated"],
                        "dateOfBirth": row["date_of_birth"], "statedAge": row["stated_age"],
                        "age": patient_age(row["date_of_birth"], row["stated_age"]),
                        "gender": row["gender"], "phone": row["phone"], "email": row["email"],
                        "address": row["address"], "occupation": row["occupation"],
                        "profileNote": row["profile_note"]},
            "agentID": row["agent_id"], "agentName": row["agent_name"], "agencyName": row["agency_name"],
            "assignedDoctorID": row["assigned_doctor_id"],
            "uploadedAt": row["uploaded_at"], "status": row["status"], "photoCount": len(photos),
            "agentNote": row["agent_note"], "agentGrafts": row["agent_grafts"],
            "currency": row["currency"], "agentPrice": row["agent_price"],
            "finalGrafts": row["final_grafts"], "finalPrice": row["final_price"],
            "finalizedAt": row["finalized_at"],
            "messages": [{"id": m["id"], "authorID": m["author_id"],
                          "author": m["author_name"], "role": m["role"],
                          "createdAt": m["created_at"], "text": m["text"],
                          "approximateGrafts": m["approximate_grafts"], "recommendedPrice": m["recommended_price"],
                          "attachmentPhotoID": m["id"] if m["attachment_path"] else None}
                         for m in messages],
            "photoIDs": [p["id"] for p in photos],
        }


class APIServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], database: Database):
        super().__init__(address, APIHandler)
        self.database = database
        self.changes = ChangeBroker()


class APIHandler(BaseHTTPRequestHandler):
    server: APIServer
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_PATCH(self) -> None:  # noqa: N802
        self._dispatch("PATCH")

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch("DELETE")

    def _dispatch(self, method: str) -> None:
        try:
            parsed = urlparse(self.path)
            path = parsed.path.rstrip("/") or "/"
            if path == "/mcp":
                return self._proxy_mcp(method, parsed.query)
            self._enforce_mcp_route_scope(method, path)
            if method == "GET" and path in {"/", f"{API_PREFIX}/admin"}:
                return self._redirect("/admin")
            if method == "GET" and (path == "/admin" or path.startswith("/admin/")):
                return self._serve_admin(path)
            if method == "GET" and path == f"{API_PREFIX}/health":
                return self._json(200, {"status": "ok", "apiVersion": "v1", "service": "Customer Flow",
                                        "capabilities": ["cases", "patient-matching", "patient-profile", "photos", "photo-messages", "role-auth", "profile", "password-reset", "live-updates", "agency-scoping", "idempotent-writes", "agency-mcp"]})
            if method == "POST" and path == f"{API_PREFIX}/auth/login":
                payload = self._read_json()
                return self._json(200, self.server.database.login(str(payload.get("username", "")), str(payload.get("password", ""))))
            if method == "POST" and path == f"{API_PREFIX}/auth/password-reset/request":
                return self._json(200, self.server.database.request_password_reset(self._read_json()))
            if method == "POST" and path == f"{API_PREFIX}/auth/password-reset/confirm":
                return self._json(200, self.server.database.reset_password(self._read_json()))
            token, user = self._authenticated_user(method, path)
            if method == "GET" and path == f"{API_PREFIX}/events":
                raw_since = parse_qs(parsed.query).get("since", ["0"])[0]
                try:
                    since = int(raw_since)
                except ValueError:
                    raise APIError(422, "invalid_revision", "The event revision must be a number.")
                return self._json(200, self.server.changes.wait(since))
            if method == "GET" and path == f"{API_PREFIX}/auth/me":
                return self._json(200, {"user": self.server.database._public_user(user)})
            if method == "POST" and path == f"{API_PREFIX}/auth/logout":
                self._read_json()
                self.server.database.logout(token)
                return self._json(200, {"ok": True})
            if method == "PATCH" and path == f"{API_PREFIX}/auth/profile":
                updated = self.server.database.update_profile(self._read_json(), user)
                return self._changed(200, {"user": updated}, "user.updated", updated["id"], user)
            if method == "POST" and path == f"{API_PREFIX}/auth/change-password":
                return self._json(200, self.server.database.change_password(self._read_json(), user, token))
            if method == "GET" and path == f"{API_PREFIX}/admin/users":
                return self._json(200, {"users": self.server.database.admin_users(user)})
            if method == "POST" and path == f"{API_PREFIX}/admin/users":
                created = self.server.database.admin_create_user(self._read_json(), user)
                return self._changed(201, {"user": created}, "user.created", created["id"], user)
            if method == "GET" and path == f"{API_PREFIX}/admin/agencies":
                return self._json(200, {"agencies": self.server.database.admin_agencies(user)})
            if method == "POST" and path == f"{API_PREFIX}/admin/agencies":
                created = self.server.database.admin_create_agency(self._read_json(), user)
                return self._changed(201, {"agency": created}, "agency.created", created["id"], user)
            if method == "GET" and path == f"{API_PREFIX}/admin/cases":
                return self._json(200, {"cases": self.server.database.admin_cases(user)})
            admin_parts = path.removeprefix(f"{API_PREFIX}/admin/").split("/")
            if (path.startswith(f"{API_PREFIX}/admin/") and method == "GET" and
                    len(admin_parts) == 3 and admin_parts[0] == "agencies" and admin_parts[2] == "mcp"):
                return self._json(
                    200, {"connection": self.server.database.admin_mcp_connection(admin_parts[1], user)}
                )
            if (path.startswith(f"{API_PREFIX}/admin/") and method == "POST" and
                    len(admin_parts) == 4 and admin_parts[0] == "agencies" and
                    admin_parts[2:] == ["mcp", "rotate"]):
                self._read_json()
                connection = self.server.database.admin_rotate_mcp_token(admin_parts[1], user)
                return self._changed(
                    200, {"connection": connection}, "agency.mcp_token_rotated", admin_parts[1], user
                )
            if path.startswith(f"{API_PREFIX}/admin/") and method == "DELETE" and len(admin_parts) == 2 and admin_parts[0] == "users":
                self._read_json()
                deleted = self.server.database.admin_delete_user(admin_parts[1], user)
                return self._changed(200, {"user": deleted}, "user.deleted", admin_parts[1], user)
            if path.startswith(f"{API_PREFIX}/admin/") and method == "DELETE" and len(admin_parts) == 2 and admin_parts[0] == "photos":
                self._read_json()
                purged = self.server.database.admin_purge_photo(admin_parts[1], user)
                return self._changed(200, {"photo": purged}, "photo.purged", admin_parts[1], user)
            if path.startswith(f"{API_PREFIX}/admin/") and method == "DELETE" and len(admin_parts) == 2 and admin_parts[0] == "cases":
                self._read_json()
                deleted = self.server.database.admin_delete_case(admin_parts[1].lower(), user)
                return self._changed(200, {"case": deleted}, "case.deleted", admin_parts[1], user)
            if path.startswith(f"{API_PREFIX}/admin/") and method == "PATCH" and len(admin_parts) == 2:
                if admin_parts[0] == "users":
                    payload = self._read_json()
                    if "active" in payload and len(payload) == 1:
                        updated = self.server.database.admin_set_user_active(
                            admin_parts[1], bool(payload.get("active")), user
                        )
                    else:
                        updated = self.server.database.admin_update_user(admin_parts[1], payload, user)
                    return self._changed(200, {"user": updated}, "user.updated", admin_parts[1], user)
                if admin_parts[0] == "patients":
                    assignment = self.server.database.admin_assign_doctor(admin_parts[1], self._read_json(), user)
                    return self._changed(
                        200, {"assignment": assignment}, "doctor.assigned", admin_parts[1], user
                    )
                if admin_parts[0] == "agencies":
                    updated = self.server.database.admin_update_agency(admin_parts[1], self._read_json(), user)
                    return self._changed(200, {"agency": updated}, "agency.updated", admin_parts[1], user)
            if method == "GET" and path == f"{API_PREFIX}/cases":
                return self._json(200, {"cases": self.server.database.fetch_cases(user)})
            if method == "POST" and path == f"{API_PREFIX}/cases":
                created = self.server.database.create_case(
                    self._read_json(), user, self.headers.get("Idempotency-Key")
                )
                if isinstance(created, IdempotentReplay):
                    return self._json(201, {"case": created})
                return self._changed(201, {"case": created}, "case.created", created["id"], user)
            if method == "GET" and path == f"{API_PREFIX}/patients/matches":
                name = parse_qs(parsed.query).get("name", [""])[0]
                return self._json(200, {"matches": self.server.database.find_matches(name, user)})
            if method == "GET" and path.startswith(f"{API_PREFIX}/photos/"):
                photo_id = path.removeprefix(f"{API_PREFIX}/photos/")
                if not photo_id or "/" in photo_id:
                    raise APIError(404, "photo_not_found", "The photo could not be found.")
                body, content_type = self.server.database.get_photo(photo_id, user)
                return self._binary(200, body, content_type)
            if method == "GET" and path.startswith(f"{API_PREFIX}/message-photos/"):
                message_id = path.removeprefix(f"{API_PREFIX}/message-photos/")
                if not message_id or "/" in message_id:
                    raise APIError(404, "message_photo_not_found", "The message photo could not be found.")
                body, content_type = self.server.database.get_message_photo(message_id, user)
                return self._binary(200, body, content_type)
            parts = path.removeprefix(f"{API_PREFIX}/cases/").split("/")
            if not path.startswith(f"{API_PREFIX}/cases/") or not parts[0]:
                raise APIError(404, "not_found", "Endpoint not found.")
            case_id = parts[0].lower()
            if method == "GET" and len(parts) == 1:
                return self._json(200, {"case": self.server.database.get_case(case_id, user)})
            action = parts[1] if len(parts) > 1 else ""
            if method == "POST" and action in {"doctor-messages", "recommendations"}:
                updated = self.server.database.send_recommendation(case_id, self._read_json(), user)
                return self._changed(200, {"case": updated}, "message.created", case_id, user)
            if method == "PATCH" and action == "agent-values":
                updated = self.server.database.save_agent_values(case_id, self._read_json(), user)
                return self._changed(200, {"case": updated}, "case.updated", case_id, user)
            if method == "POST" and action == "agent-updates":
                updated = self.server.database.add_agent_update(
                    case_id, self._read_json(), user, self.headers.get("Idempotency-Key")
                )
                if isinstance(updated, IdempotentReplay):
                    return self._json(200, {"case": updated})
                return self._changed(200, {"case": updated}, "message.created", case_id, user)
            if method == "POST" and action == "close":
                updated = self.server.database.close_case(case_id, self._read_json(), user)
                return self._changed(200, {"case": updated}, "case.closed", case_id, user)
            if method == "POST" and action == "photos":
                body = self.rfile.read(self._content_length())
                content_type = self.headers.get("Content-Type", "application/octet-stream").split(";", 1)[0]
                updated = self.server.database.add_photo(
                    case_id, body, content_type, user, self.headers.get("Idempotency-Key")
                )
                if isinstance(updated, IdempotentReplay):
                    return self._json(201, {"case": updated})
                return self._changed(201, {"case": updated}, "photo.created", case_id, user)
            if method == "POST" and action == "message-photos":
                body = self.rfile.read(self._content_length())
                content_type = self.headers.get("Content-Type", "application/octet-stream").split(";", 1)[0]
                message_text = message_text_from_header(self.headers.get("X-Message-Text"))
                updated = self.server.database.add_message_photo(
                    case_id, body, content_type, message_text, user
                )
                return self._changed(201, {"case": updated}, "message.created", case_id, user)
            if method == "DELETE" and action == "photos" and len(parts) == 3:
                self._read_json()
                updated = self.server.database.delete_photo(case_id, parts[2], user)
                return self._changed(200, {"case": updated}, "photo.deleted", case_id, user)
            if method == "DELETE" and action == "messages" and len(parts) == 3:
                self._read_json()
                updated = self.server.database.delete_message(case_id, parts[2], user)
                return self._changed(200, {"case": updated}, "message.deleted", case_id, user)
            raise APIError(404, "not_found", "Endpoint not found.")
        except APIError as exc:
            self._json(exc.status, {"error": {"code": exc.code, "message": exc.message, "details": exc.details}})
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json(400, {"error": {"code": "invalid_json", "message": "Request body must be valid JSON."}})
        except Exception as exc:
            self.log_error("Unhandled API error: %r", exc)
            self._json(500, {"error": {"code": "internal_error", "message": "The server could not complete the request."}})

    def _proxy_mcp(self, method: str, query: str) -> None:
        """Expose the loopback MCP service through the existing public API origin."""
        if method not in {"GET", "POST", "DELETE"}:
            raise APIError(405, "method_not_allowed", "This MCP method is not supported.")
        length = self._content_length()
        if length > 16 * 1024 * 1024:
            raise APIError(413, "body_too_large", "The MCP request body is too large.")
        body = self.rfile.read(length) if length else None
        upstream = urlparse(os.getenv("CF_MCP_UPSTREAM_URL", "http://127.0.0.1:8091/mcp"))
        if upstream.scheme != "http" or upstream.hostname not in {"127.0.0.1", "localhost", "::1"}:
            raise RuntimeError("CF_MCP_UPSTREAM_URL must use loopback HTTP.")
        target = upstream.path or "/mcp"
        if query:
            target = f"{target}?{query}"
        request_headers = {
            name: value
            for name in (
                "Accept", "Authorization", "Content-Type", "Last-Event-ID",
                "MCP-Protocol-Version", "Mcp-Session-Id",
            )
            if (value := self.headers.get(name))
        }
        connection = http.client.HTTPConnection(
            upstream.hostname, upstream.port or 80, timeout=65
        )
        try:
            connection.request(method, target, body=body, headers=request_headers)
            response = connection.getresponse()
            payload = response.read()
            self.send_response(response.status)
            for name in (
                "Content-Type", "Allow", "MCP-Session-Id", "WWW-Authenticate",
            ):
                if value := response.getheader(name):
                    self.send_header(name, value)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (OSError, http.client.HTTPException):
            raise APIError(503, "mcp_unavailable", "The MCP service is unavailable.") from None
        finally:
            connection.close()

    @staticmethod
    def _mcp_route_allowed(method: str, path: str) -> bool:
        """Keep agency integration tokens out of every non-MCP API workflow."""
        if (method, path) in {
            ("GET", f"{API_PREFIX}/auth/me"),
            ("GET", f"{API_PREFIX}/cases"),
            ("POST", f"{API_PREFIX}/cases"),
        }:
            return True
        prefix = f"{API_PREFIX}/cases/"
        if not path.startswith(prefix):
            return False
        parts = path.removeprefix(prefix).split("/")
        if method == "GET" and len(parts) == 1 and parts[0]:
            return True
        return (
            method == "POST"
            and len(parts) == 2
            and bool(parts[0])
            and parts[1] in {"agent-updates", "photos"}
        )

    def _enforce_mcp_route_scope(self, method: str, path: str) -> None:
        """Reject scoped bearer credentials even on routes handled before normal auth."""
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return
        token = header.removeprefix("Bearer ").strip()
        if not token.startswith("cfmcp_"):
            return
        self.server.database.authenticate_mcp_token(token)
        if not self._mcp_route_allowed(method, path):
            raise APIError(
                403,
                "mcp_scope_forbidden",
                "The agency MCP token is not permitted to use this endpoint.",
            )

    def _authenticated_user(self, method: str, path: str) -> tuple[str, sqlite3.Row]:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise APIError(401, "authentication_required", "Sign in to continue.")
        token = header.removeprefix("Bearer ").strip()
        if token.startswith("cfmcp_"):
            principal = self.server.database.authenticate_mcp_token(token)
            if not self._mcp_route_allowed(method, path):
                raise APIError(
                    403,
                    "mcp_scope_forbidden",
                    "The agency MCP token is not permitted to use this endpoint.",
                )
            user = self.server.database.mcp_service_user(
                principal["serviceUserID"], principal["agencyID"]
            )
            return token, user
        return token, self.server.database.authenticate(token)

    def _content_length(self) -> int:
        try:
            return max(0, int(self.headers.get("Content-Length", "0")))
        except ValueError:
            raise APIError(400, "invalid_content_length", "Invalid Content-Length header.")

    def _read_json(self) -> dict:
        length = self._content_length()
        if length > 2 * 1024 * 1024:
            raise APIError(413, "body_too_large", "JSON request body is too large.")
        raw = self.rfile.read(length)
        value = json.loads(raw.decode() or "{}")
        if not isinstance(value, dict):
            raise APIError(400, "invalid_json", "JSON request body must be an object.")
        return value

    def _serve_admin(self, path: str) -> None:
        filename = {
            "/admin": "index.html",
            "/admin/index.html": "index.html",
            "/admin/admin.css": "admin.css",
            "/admin/admin.js": "admin.js",
        }.get(path)
        if not filename:
            raise APIError(404, "not_found", "Admin asset not found.")
        default_admin_dir = Path(__file__).resolve().parent.parent / "admin-panel"
        admin_dir = Path(os.getenv("CF_ADMIN_DIR", str(default_admin_dir))).expanduser().resolve()
        file_path = admin_dir / filename
        if not file_path.is_file():
            raise APIError(404, "not_found", "Admin panel is not installed.")
        content_type = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8"}[file_path.suffix]
        body = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store" if filename == "index.html" else "public, max-age=300")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(body)

    def _redirect(self, location: str) -> None:
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _changed(
        self,
        status: int,
        payload: dict,
        kind: str,
        entity_id: str | None,
        user: sqlite3.Row,
    ) -> None:
        self.server.changes.publish(kind, entity_id, user["id"])
        self._json(status, payload)

    def _binary(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "private, no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        print(f"{self.address_string()} - {format % args}")


def create_server(host: str, port: int, db_path: Path, media_root: Path, seed: bool = True) -> APIServer:
    database = Database(db_path, media_root)
    database.initialize(seed=seed)
    return APIServer((host, port), database)


def main() -> None:
    parser = argparse.ArgumentParser(description="Customer Flow local API")
    parser.add_argument("--host", default=os.getenv("CF_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.getenv("CF_PORT", "8080")))
    parser.add_argument("--db", type=Path, default=Path(os.getenv("CF_DB_PATH", "data/customer-flow.sqlite3")))
    parser.add_argument("--media", type=Path, default=Path(os.getenv("CF_MEDIA_ROOT", "media")))
    parser.add_argument("--no-seed", action="store_true")
    args = parser.parse_args()
    server = create_server(args.host, args.port, args.db, args.media, seed=not args.no_seed)
    print(f"Customer Flow API listening on http://{args.host}:{args.port}{API_PREFIX}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
