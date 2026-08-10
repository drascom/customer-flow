#!/usr/bin/env python3
"""Customer Flow local API.

Dependency-free HTTP + SQLite service for the first native vertical slice.
Production deployments must place it behind an HTTPS reverse proxy.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import secrets
import smtplib
import sqlite3
import threading
import unicodedata
import uuid
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


API_PREFIX = "/api/v1"
UTC = timezone.utc


def utc_now() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


def iso(value: datetime | str) -> str:
    if isinstance(value, str):
        return value
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def normalize_name(value: str) -> tuple[str, set[str]]:
    folded = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    tokens = {"".join(ch for ch in part.casefold() if ch.isalnum()) for part in folded.split()}
    tokens.discard("")
    return " ".join(sorted(tokens)), tokens


def hash_password(password: str, salt: bytes | None = None) -> tuple[str, str]:
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 210_000)
    return salt.hex(), digest.hex()


class APIError(Exception):
    def __init__(self, status: int, code: str, message: str, details: object | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details


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
  role TEXT NOT NULL CHECK(role IN ('doctor','agent','admin')),
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
  version INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_cases_doctor_status ON cases(assigned_doctor_id, status);
CREATE INDEX IF NOT EXISTS idx_cases_agent ON cases(agent_id, uploaded_at);
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users(id),
  author_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('doctor','agent','system')),
  created_at TEXT NOT NULL,
  text TEXT NOT NULL,
  approximate_grafts TEXT,
  recommended_price TEXT
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
                conn.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email COLLATE NOCASE) "
                    "WHERE email IS NOT NULL AND email <> ''"
                )
            self.ensure_demo_agencies()
            if seed:
                self.seed_demo()

    def ensure_demo_agencies(self) -> None:
        now = iso(utc_now())
        agencies = [
            ("agency-drascom", "Drascom Partner"),
            ("agency-north", "North Clinic Partners"),
            ("agency-anatolia", "Anatolia Medical"),
        ]
        with self.connect() as conn:
            for agency_id, name in agencies:
                conn.execute("INSERT OR IGNORE INTO agencies VALUES (?,?,1,?)", (agency_id, name, now))
            conn.execute("UPDATE users SET agency_id='agency-drascom' WHERE username='agent' AND agency_id IS NULL")
            conn.execute("UPDATE users SET agency_id='agency-north' WHERE username IN ('mert','cem') AND agency_id IS NULL")
            conn.execute("UPDATE users SET agency_id='agency-anatolia' WHERE username='aylin' AND agency_id IS NULL")

    def seed_demo(self) -> None:
        with self.connect() as conn:
            if conn.execute("SELECT 1 FROM users LIMIT 1").fetchone():
                return
            now = iso(utc_now())
            demo_users = [
                ("doctor-emre", "doctor", "Dr. Emre Kaya", "doctor", None, os.getenv("CF_DOCTOR_PASSWORD", "doctor123")),
                ("agent-selin", "agent", "Selin Arslan", "agent", "agency-drascom", os.getenv("CF_AGENT_PASSWORD", "agent123")),
                ("admin-local", "admin", "Local Admin", "admin", None, os.getenv("CF_ADMIN_PASSWORD", "admin123")),
                ("agent-mert", "mert", "Mert Demir", "agent", "agency-north", secrets.token_urlsafe(24)),
                ("agent-aylin", "aylin", "Aylin Yılmaz", "agent", "agency-anatolia", secrets.token_urlsafe(24)),
                ("agent-cem", "cem", "Cem Öztürk", "agent", "agency-north", secrets.token_urlsafe(24)),
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
                    ("HT-240821", "PT-1060", "Ethan Cole", "agent-aylin", None, 2, "waiting", 4, "1,800", "2,100", "Second opinion requested after a previous FUE procedure. Please review corrective options.", False),
                    ("HT-240803", "PT-1037", "Noah Bennett", "agent-selin", "doctor-emre", 28, "answered", 3, "2,600", "2,500", "Receding hairline with good donor density. Recommendation is waiting for agent confirmation.", True),
                    ("HT-240799", "PT-1029", "Oliver Grant", "agent-cem", "doctor-emre", 48, "answered", 4, "3,000", "2,800", "Crown-focused case. Recommendation has been sent.", True),
                    ("HT-240764", "PT-0998", "George Hall", "agent-aylin", "doctor-emre", 96, "closed", 3, "2,200", "2,300", "Frontal restoration consultation completed and confirmed.", True),
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
            "INSERT INTO patients VALUES (?,?,?,?,NULL,?)",
            (patient_id, patient_name, normalized, doctor_id, iso(created)),
        )
        case_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"customer-flow:{reference}"))
        conn.execute(
            "INSERT INTO cases VALUES (?,?,?,?,?,?,?,?,?,?,?,?,1)",
            (case_id, reference, patient_id, agent_id, doctor_id, iso(created), status, photo_count, note, grafts, "EUR", price),
        )
        agent = conn.execute("SELECT display_name FROM users WHERE id=?", (agent_id,)).fetchone()[0]
        conn.execute(
            "INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?)",
            (str(uuid.uuid4()), case_id, agent_id, agent, "agent", iso(created), "Patient photos and consultation information uploaded.", None, None),
        )
        for position in range(photo_count):
            conn.execute(
                "INSERT INTO photos VALUES (?,?,?,?,?,?,?)",
                (str(uuid.uuid4()), case_id, position, None, None, agent_id, iso(created)),
            )
        if doctor_reply:
            conn.execute(
                "INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?)",
                (str(uuid.uuid4()), case_id, "doctor-emre", "Dr. Emre Kaya", "doctor", iso(created + timedelta(hours=1)),
                 "The donor area appears suitable, subject to an in-person density measurement.", "2,400–2,700", "€2,600"),
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
        if user["role"] == "doctor":
            where, params = "WHERE c.assigned_doctor_id=? OR c.assigned_doctor_id IS NULL", [user["id"]]
        elif user["role"] == "agent":
            where, params = "WHERE c.agent_id=?", [user["id"]]
        with self.connect() as conn:
            rows = conn.execute(
                f"SELECT c.*, p.name patient_name, p.assigned_doctor_id patient_doctor, p.last_updated, "
                f"u.display_name agent_name FROM cases c JOIN patients p ON p.id=c.patient_id "
                f"JOIN users u ON u.id=c.agent_id {where} ORDER BY c.uploaded_at ASC",
                params,
            ).fetchall()
            return [self._case_json(conn, row) for row in rows]

    def get_case(self, case_id: str, user: sqlite3.Row) -> dict:
        with self.connect() as conn:
            row = self._case_row(conn, case_id)
            self._assert_case_visible(row, user)
            return self._case_json(conn, row)

    def find_matches(self, name: str, user: sqlite3.Row) -> list[dict]:
        _, query_tokens = normalize_name(name)
        if len(query_tokens) < 2:
            return []
        with self.connect() as conn:
            patients = conn.execute("SELECT * FROM patients ORDER BY last_updated DESC").fetchall()
            result = []
            for patient in patients:
                _, patient_tokens = normalize_name(patient["name"])
                if not query_tokens.issubset(patient_tokens):
                    continue
                latest = conn.execute(
                    "SELECT c.*, a.display_name agent_name FROM cases c JOIN users a ON a.id=c.agent_id "
                    "WHERE c.patient_id=? ORDER BY c.uploaded_at DESC LIMIT 1", (patient["id"],)
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

    def create_case(self, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "agent")
        required = ["patientName", "grafts", "currency", "price", "note", "photoCount"]
        missing = [key for key in required if payload.get(key) in (None, "")]
        if missing:
            raise APIError(422, "missing_fields", "Required case information is missing.", missing)
        name = str(payload["patientName"]).strip()
        normalized, query_tokens = normalize_name(name)
        if len(query_tokens) < 2:
            raise APIError(422, "full_name_required", "Enter the patient's first and last name.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                candidates = conn.execute("SELECT id,name FROM patients WHERE normalized_name=?", (normalized,)).fetchall()
                existing_id = payload.get("existingPatientID")
                confirmed_different = bool(payload.get("duplicateConfirmedDifferent"))
                if candidates and not existing_id and not confirmed_different:
                    raise APIError(409, "duplicate_confirmation_required", "A previous consultation may exist for this patient.",
                                   [{"id": row["id"], "name": row["name"]} for row in candidates])
                if existing_id:
                    patient = conn.execute("SELECT * FROM patients WHERE id=?", (existing_id,)).fetchone()
                    if not patient:
                        raise APIError(404, "patient_not_found", "The selected patient could not be found.")
                    patient_id = patient["id"]
                    assigned_doctor = patient["assigned_doctor_id"]
                    conn.execute("UPDATE patients SET last_updated=? WHERE id=?", (iso(utc_now()), patient_id))
                else:
                    patient_id = self._next_reference(conn, "patient_reference", "PT-")
                    assigned_doctor = None
                    conn.execute("INSERT INTO patients VALUES (?,?,?,?,NULL,?)",
                                 (patient_id, name, normalized, None, iso(utc_now())))
                case_id = str(uuid.uuid4())
                reference = self._next_reference(conn, "case_reference", "HT-")
                now = iso(utc_now())
                photo_count = max(0, int(payload["photoCount"]))
                conn.execute(
                    "INSERT INTO cases VALUES (?,?,?,?,?,?,?,?,?,?,?,?,1)",
                    (case_id, reference, patient_id, user["id"], assigned_doctor, now, "waiting", photo_count,
                     str(payload["note"]), str(payload["grafts"]), str(payload["currency"]), str(payload["price"])),
                )
                conn.execute("INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?)",
                             (str(uuid.uuid4()), case_id, user["id"], user["display_name"], "agent", now,
                              "Patient photos and consultation information uploaded.", None, None))
                for position in range(photo_count):
                    conn.execute("INSERT INTO photos VALUES (?,?,?,?,?,?,?)",
                                 (str(uuid.uuid4()), case_id, position, None, None, user["id"], now))
                self._audit(conn, user["id"], "case.created", "case", case_id,
                            {"reference": reference, "duplicateConfirmedDifferent": confirmed_different})
                row = self._case_row(conn, case_id)
                result = self._case_json(conn, row)
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def send_recommendation(self, case_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "doctor")
        for key in ("approximateGrafts", "recommendedPrice", "text"):
            if not str(payload.get(key, "")).strip():
                raise APIError(422, "missing_fields", "Complete all recommendation fields.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = self._case_row(conn, case_id)
                if row["status"] != "waiting" or row["assigned_doctor_id"] not in (None, user["id"]):
                    raise APIError(409, "case_changed", "This case was already answered or assigned. Refresh to continue.")
                now = iso(utc_now())
                conn.execute("UPDATE cases SET assigned_doctor_id=?, status='answered', version=version+1 WHERE id=?",
                             (user["id"], case_id))
                conn.execute("UPDATE patients SET assigned_doctor_id=?, last_updated=? WHERE id=?",
                             (user["id"], now, row["patient_id"]))
                conn.execute("INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?)",
                             (str(uuid.uuid4()), case_id, user["id"], user["display_name"], "doctor", now,
                              str(payload["text"]), str(payload["approximateGrafts"]), str(payload["recommendedPrice"])))
                self._audit(conn, user["id"], "case.recommended", "case", case_id, {})
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
                conn.execute("UPDATE patients SET name=?, normalized_name=?, last_updated=? WHERE id=?",
                             (name, normalized, iso(utc_now()), row["patient_id"]))
                conn.execute("UPDATE cases SET agent_grafts=?, currency=?, agent_price=?, version=version+1 WHERE id=?",
                             (str(payload["grafts"]), str(payload["currency"]), str(payload["price"]), case_id))
                self._audit(conn, user["id"], "case.agent_values_updated", "case", case_id, {})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def add_agent_update(self, case_id: str, payload: dict, user: sqlite3.Row) -> dict:
        self._require_role(user, "agent")
        text = str(payload.get("text", "")).strip()
        if not text:
            raise APIError(422, "empty_update", "Write an update before sending.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = self._case_row(conn, case_id)
                self._assert_owner(row, user)
                if row["status"] == "closed":
                    raise APIError(409, "case_closed", "A closed case cannot be updated.")
                now = iso(utc_now())
                conn.execute("INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?)",
                             (str(uuid.uuid4()), case_id, user["id"], user["display_name"], "agent", now, text, None, None))
                conn.execute("UPDATE cases SET status='waiting', version=version+1 WHERE id=?", (case_id,))
                self._audit(conn, user["id"], "case.agent_update_added", "case", case_id, {})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def close_case(self, case_id: str, user: sqlite3.Row) -> dict:
        self._require_role(user, "agent")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = self._case_row(conn, case_id)
                self._assert_owner(row, user)
                if row["status"] != "answered":
                    raise APIError(409, "not_ready_to_close", "Only an answered case can be confirmed and closed.")
                conn.execute("UPDATE cases SET status='closed', version=version+1 WHERE id=?", (case_id,))
                self._audit(conn, user["id"], "case.closed", "case", case_id, {})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def add_photo(self, case_id: str, body: bytes, content_type: str, user: sqlite3.Row) -> dict:
        self._require_role(user, "agent")
        if not body or len(body) > 20 * 1024 * 1024:
            raise APIError(422, "invalid_photo", "Photo must be between 1 byte and 20 MB.")
        extension = {"image/jpeg": ".jpg", "image/png": ".png", "image/heic": ".heic"}.get(content_type)
        if not extension:
            raise APIError(415, "unsupported_photo", "Use JPEG, PNG or HEIC photos.")
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = self._case_row(conn, case_id)
                self._assert_owner(row, user)
                photo_id = str(uuid.uuid4())
                case_dir = self.media_root / case_id
                case_dir.mkdir(parents=True, exist_ok=True)
                path = case_dir / f"{photo_id}{extension}"
                path.write_bytes(body)
                position = conn.execute("SELECT COALESCE(MAX(position),-1)+1 FROM photos WHERE case_id=?", (case_id,)).fetchone()[0]
                now = iso(utc_now())
                conn.execute("INSERT INTO photos VALUES (?,?,?,?,?,?,?)",
                             (photo_id, case_id, position, str(path.relative_to(self.media_root)), content_type, user["id"], now))
                conn.execute("UPDATE cases SET photo_count=photo_count+1, status='waiting', version=version+1 WHERE id=?", (case_id,))
                self._audit(conn, user["id"], "case.photo_added", "case", case_id, {"photoID": photo_id})
                result = self._case_json(conn, self._case_row(conn, case_id))
                conn.execute("COMMIT")
                return result
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def get_photo(self, photo_id: str, user: sqlite3.Row) -> tuple[bytes, str]:
        with self.connect() as conn:
            photo = conn.execute("SELECT * FROM photos WHERE id=?", (photo_id,)).fetchone()
            if not photo:
                raise APIError(404, "photo_not_found", "The photo could not be found.")
            case = self._case_row(conn, photo["case_id"])
            self._assert_case_visible(case, user)
            if not photo["file_path"] or not photo["content_type"]:
                raise APIError(404, "photo_not_found", "The photo file is not available.")
            media_root = self.media_root.resolve()
            file_path = (media_root / photo["file_path"]).resolve()
            if not file_path.is_relative_to(media_root) or not file_path.is_file():
                raise APIError(404, "photo_not_found", "The photo file is not available.")
            return file_path.read_bytes(), photo["content_type"]

    def admin_users(self, user: sqlite3.Row) -> list[dict]:
        self._require_role(user, "admin")
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT u.*, ag.name agency_name, "
                "(SELECT COUNT(*) FROM cases c WHERE c.agent_id=u.id) agent_case_count, "
                "(SELECT COUNT(*) FROM patients p WHERE p.assigned_doctor_id=u.id) doctor_patient_count "
                "FROM users u LEFT JOIN agencies ag ON ag.id=u.agency_id "
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
        if not username or not display_name or role not in {"doctor", "agent", "admin"}:
            raise APIError(422, "invalid_user", "Username, display name and a valid role are required.")
        if len(password) < 10:
            raise APIError(422, "weak_password", "The temporary password must contain at least 10 characters.")
        if any(ch.isspace() for ch in username):
            raise APIError(422, "invalid_username", "Username cannot contain spaces.")
        agency_id = str(payload.get("agencyID", "")).strip() or None
        user_id = f"{role}-{uuid.uuid4().hex[:12]}"
        salt, digest = hash_password(password)
        with self.connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
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
        self._require_role(user, "admin")
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT ag.*, (SELECT COUNT(*) FROM users u WHERE u.agency_id=ag.id) user_count "
                "FROM agencies ag ORDER BY ag.active DESC, ag.name"
            ).fetchall()
            return [{"id": row["id"], "name": row["name"], "active": bool(row["active"]),
                     "userCount": row["user_count"]} for row in rows]

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
                return {"id": agency_id, "name": name, "active": True, "userCount": 0}
            except sqlite3.IntegrityError:
                conn.execute("ROLLBACK")
                raise APIError(409, "agency_exists", "An agency with this name already exists.")
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def admin_cases(self, user: sqlite3.Row) -> list[dict]:
        self._require_role(user, "admin")
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT c.id,c.reference,c.uploaded_at,c.status,c.photo_count,c.agent_grafts,c.currency,c.agent_price,"
                "p.id patient_id,p.name patient_name,p.assigned_doctor_id,"
                "a.display_name agent_name,ag.name agency_name,d.display_name doctor_name,"
                "(SELECT COUNT(*) FROM messages m WHERE m.case_id=c.id) message_count "
                "FROM cases c JOIN patients p ON p.id=c.patient_id "
                "JOIN users a ON a.id=c.agent_id LEFT JOIN agencies ag ON ag.id=a.agency_id "
                "LEFT JOIN users d ON d.id=p.assigned_doctor_id "
                "ORDER BY c.uploaded_at DESC"
            ).fetchall()
            return [{
                "id": row["id"], "reference": row["reference"], "patientID": row["patient_id"],
                "patientName": row["patient_name"], "agentName": row["agent_name"],
                "agencyName": row["agency_name"],
                "doctorID": row["assigned_doctor_id"], "doctorName": row["doctor_name"],
                "uploadedAt": row["uploaded_at"], "status": row["status"],
                "photoCount": row["photo_count"], "messageCount": row["message_count"],
                "grafts": row["agent_grafts"], "currency": row["currency"], "price": row["agent_price"],
            } for row in rows]

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
    def _assert_owner(case: sqlite3.Row, user: sqlite3.Row) -> None:
        if case["agent_id"] != user["id"]:
            raise APIError(403, "forbidden", "You cannot change another agent's case.")

    @staticmethod
    def _assert_case_visible(case: sqlite3.Row, user: sqlite3.Row) -> None:
        if user["role"] == "doctor" and case["assigned_doctor_id"] not in (None, user["id"]):
            raise APIError(403, "forbidden", "This case is assigned to another doctor.")
        if user["role"] == "agent" and case["agent_id"] != user["id"]:
            raise APIError(403, "forbidden", "This case belongs to another agent.")

    @staticmethod
    def _audit(conn: sqlite3.Connection, actor: str, action: str, entity_type: str, entity_id: str, detail: dict) -> None:
        conn.execute("INSERT INTO audit_events(actor_id,action,entity_type,entity_id,detail_json,created_at) VALUES (?,?,?,?,?,?)",
                     (actor, action, entity_type, entity_id, json.dumps(detail, separators=(",", ":")), iso(utc_now())))

    @staticmethod
    def _case_row(conn: sqlite3.Connection, case_id: str) -> sqlite3.Row:
        row = conn.execute(
            "SELECT c.*, p.name patient_name, p.assigned_doctor_id patient_doctor, p.last_updated, "
            "u.display_name agent_name FROM cases c JOIN patients p ON p.id=c.patient_id "
            "JOIN users u ON u.id=c.agent_id WHERE c.id=?", (case_id,),
        ).fetchone()
        if not row:
            raise APIError(404, "case_not_found", "The case could not be found.")
        return row

    @staticmethod
    def _case_json(conn: sqlite3.Connection, row: sqlite3.Row) -> dict:
        messages = conn.execute("SELECT * FROM messages WHERE case_id=? ORDER BY created_at,id", (row["id"],)).fetchall()
        photos = conn.execute("SELECT id,position FROM photos WHERE case_id=? ORDER BY position", (row["id"],)).fetchall()
        return {
            "id": row["id"], "reference": row["reference"],
            "patient": {"id": row["patient_id"], "name": row["patient_name"],
                        "assignedDoctorID": row["patient_doctor"], "lastUpdated": row["last_updated"]},
            "agentName": row["agent_name"], "assignedDoctorID": row["assigned_doctor_id"],
            "uploadedAt": row["uploaded_at"], "status": row["status"], "photoCount": row["photo_count"],
            "agentNote": row["agent_note"], "agentGrafts": row["agent_grafts"],
            "currency": row["currency"], "agentPrice": row["agent_price"],
            "messages": [{"id": m["id"], "author": m["author_name"], "role": m["role"],
                          "createdAt": m["created_at"], "text": m["text"],
                          "approximateGrafts": m["approximate_grafts"], "recommendedPrice": m["recommended_price"]}
                         for m in messages],
            "photoIDs": [p["id"] for p in photos],
        }


class APIServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], database: Database):
        super().__init__(address, APIHandler)
        self.database = database


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
            if method == "GET" and path in {"/", f"{API_PREFIX}/admin"}:
                return self._redirect("/admin")
            if method == "GET" and (path == "/admin" or path.startswith("/admin/")):
                return self._serve_admin(path)
            if method == "GET" and path == f"{API_PREFIX}/health":
                return self._json(200, {"status": "ok", "apiVersion": "v1", "service": "Customer Flow",
                                        "capabilities": ["cases", "patient-matching", "photos", "role-auth", "profile", "password-reset"]})
            if method == "POST" and path == f"{API_PREFIX}/auth/login":
                payload = self._read_json()
                return self._json(200, self.server.database.login(str(payload.get("username", "")), str(payload.get("password", ""))))
            if method == "POST" and path == f"{API_PREFIX}/auth/password-reset/request":
                return self._json(200, self.server.database.request_password_reset(self._read_json()))
            if method == "POST" and path == f"{API_PREFIX}/auth/password-reset/confirm":
                return self._json(200, self.server.database.reset_password(self._read_json()))
            token, user = self._authenticated_user()
            if method == "GET" and path == f"{API_PREFIX}/auth/me":
                return self._json(200, {"user": self.server.database._public_user(user)})
            if method == "POST" and path == f"{API_PREFIX}/auth/logout":
                self.server.database.logout(token)
                return self._json(200, {"ok": True})
            if method == "GET" and path.startswith(f"{API_PREFIX}/photos/"):
                photo_id = path.removeprefix(f"{API_PREFIX}/photos/")
                if not photo_id or "/" in photo_id:
                    raise APIError(404, "photo_not_found", "The photo could not be found.")
                body, content_type = self.server.database.get_photo(photo_id, user)
                return self._binary(200, body, content_type)
            if method == "PATCH" and path == f"{API_PREFIX}/auth/profile":
                return self._json(200, {"user": self.server.database.update_profile(self._read_json(), user)})
            if method == "POST" and path == f"{API_PREFIX}/auth/change-password":
                return self._json(200, self.server.database.change_password(self._read_json(), user, token))
            if method == "GET" and path == f"{API_PREFIX}/admin/users":
                return self._json(200, {"users": self.server.database.admin_users(user)})
            if method == "POST" and path == f"{API_PREFIX}/admin/users":
                return self._json(201, {"user": self.server.database.admin_create_user(self._read_json(), user)})
            if method == "GET" and path == f"{API_PREFIX}/admin/agencies":
                return self._json(200, {"agencies": self.server.database.admin_agencies(user)})
            if method == "POST" and path == f"{API_PREFIX}/admin/agencies":
                return self._json(201, {"agency": self.server.database.admin_create_agency(self._read_json(), user)})
            if method == "GET" and path == f"{API_PREFIX}/admin/cases":
                return self._json(200, {"cases": self.server.database.admin_cases(user)})
            admin_parts = path.removeprefix(f"{API_PREFIX}/admin/").split("/")
            if path.startswith(f"{API_PREFIX}/admin/") and method == "DELETE" and len(admin_parts) == 2 and admin_parts[0] == "users":
                return self._json(200, {"user": self.server.database.admin_delete_user(admin_parts[1], user)})
            if path.startswith(f"{API_PREFIX}/admin/") and method == "PATCH" and len(admin_parts) == 2:
                if admin_parts[0] == "users":
                    payload = self._read_json()
                    return self._json(200, {"user": self.server.database.admin_set_user_active(
                        admin_parts[1], bool(payload.get("active")), user
                    )})
                if admin_parts[0] == "patients":
                    return self._json(200, {"assignment": self.server.database.admin_assign_doctor(
                        admin_parts[1], self._read_json(), user
                    )})
            if method == "GET" and path == f"{API_PREFIX}/cases":
                return self._json(200, {"cases": self.server.database.fetch_cases(user)})
            if method == "POST" and path == f"{API_PREFIX}/cases":
                return self._json(201, {"case": self.server.database.create_case(self._read_json(), user)})
            if method == "GET" and path == f"{API_PREFIX}/patients/matches":
                name = parse_qs(parsed.query).get("name", [""])[0]
                return self._json(200, {"matches": self.server.database.find_matches(name, user)})
            parts = path.removeprefix(f"{API_PREFIX}/cases/").split("/")
            if not path.startswith(f"{API_PREFIX}/cases/") or not parts[0]:
                raise APIError(404, "not_found", "Endpoint not found.")
            case_id = parts[0]
            if method == "GET" and len(parts) == 1:
                return self._json(200, {"case": self.server.database.get_case(case_id, user)})
            action = parts[1] if len(parts) > 1 else ""
            if method == "POST" and action == "recommendations":
                return self._json(200, {"case": self.server.database.send_recommendation(case_id, self._read_json(), user)})
            if method == "PATCH" and action == "agent-values":
                return self._json(200, {"case": self.server.database.save_agent_values(case_id, self._read_json(), user)})
            if method == "POST" and action == "agent-updates":
                return self._json(200, {"case": self.server.database.add_agent_update(case_id, self._read_json(), user)})
            if method == "POST" and action == "close":
                return self._json(200, {"case": self.server.database.close_case(case_id, user)})
            if method == "POST" and action == "photos":
                body = self.rfile.read(self._content_length())
                content_type = self.headers.get("Content-Type", "application/octet-stream").split(";", 1)[0]
                return self._json(201, {"case": self.server.database.add_photo(case_id, body, content_type, user)})
            raise APIError(404, "not_found", "Endpoint not found.")
        except APIError as exc:
            self._json(exc.status, {"error": {"code": exc.code, "message": exc.message, "details": exc.details}})
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json(400, {"error": {"code": "invalid_json", "message": "Request body must be valid JSON."}})
        except Exception as exc:
            self.log_error("Unhandled API error: %r", exc)
            self._json(500, {"error": {"code": "internal_error", "message": "The server could not complete the request."}})

    def _authenticated_user(self) -> tuple[str, sqlite3.Row]:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise APIError(401, "authentication_required", "Sign in to continue.")
        token = header.removeprefix("Bearer ").strip()
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

    def _binary(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "private, max-age=300")
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
