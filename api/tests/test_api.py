import json
import os
import sqlite3
import tempfile
import threading
import unittest
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

from app import Database, create_server, hash_password


class APITestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["CF_PASSWORD_RESET_TEST_CODE"] = "123456"
        cls.temp = tempfile.TemporaryDirectory()
        root = Path(cls.temp.name)
        cls.server = create_server("127.0.0.1", 0, root / "test.sqlite3", root / "media", seed=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}/api/v1"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.temp.cleanup()
        os.environ.pop("CF_PASSWORD_RESET_TEST_CODE", None)

    def request(self, method, path, payload=None, token=None, expected=200):
        body = None if payload is None else json.dumps(payload).encode()
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = Request(self.base + path, data=body, headers=headers, method=method)
        try:
            with urlopen(request) as response:
                self.assertEqual(expected, response.status)
                return json.load(response)
        except HTTPError as error:
            self.assertEqual(expected, error.code)
            return json.load(error)

    def login(self, username, password):
        return self.request("POST", "/auth/login", {"username": username, "password": password})["token"]

    def test_health_and_login(self):
        health = self.request("GET", "/health")
        self.assertEqual("ok", health["status"])
        result = self.request("POST", "/auth/login", {"username": "doctor", "password": "doctor123"})
        self.assertEqual("doctor", result["user"]["role"])

    def test_profile_password_change_and_forgotten_password(self):
        admin = self.login("admin", "admin123")
        username = "profile-" + uuid.uuid4().hex[:8]
        original_password = "Temporary!123"
        created = self.request("POST", "/admin/users", {
            "username": username, "displayName": "Profile Test", "role": "agent",
            "agencyID": "agency-drascom", "password": original_password
        }, token=admin, expected=201)["user"]
        token = self.login(username, original_password)
        email = f"{username}@example.test"
        profile = self.request("PATCH", "/auth/profile", {
            "displayName": "Updated Profile", "email": email, "phone": "+44 7700 900123"
        }, token=token)["user"]
        self.assertEqual(email, profile["email"])
        self.assertEqual("+44 7700 900123", profile["phone"])

        changed_password = "ChangedPass!123"
        self.request("POST", "/auth/change-password", {
            "currentPassword": original_password, "newPassword": changed_password
        }, token=token)
        self.request("POST", "/auth/login", {"username": username, "password": original_password}, expected=401)
        changed_token = self.login(username, changed_password)

        requested = self.request("POST", "/auth/password-reset/request", {"identifier": email})
        self.assertTrue(requested["ok"])
        reset_password = "ResetPass!123"
        self.request("POST", "/auth/password-reset/confirm", {
            "identifier": email, "code": "123456", "newPassword": reset_password
        })
        self.request("GET", "/cases", token=changed_token, expected=401)
        self.assertIsNotNone(self.login(username, reset_password))
        self.assertEqual(created["id"], profile["id"])

    def test_admin_alias_redirects_to_panel(self):
        root = self.base.removesuffix("/api/v1")
        with urlopen(root + "/api/v1/admin") as response:
            self.assertEqual(200, response.status)
            self.assertEqual(root + "/admin", response.url)
            body = response.read()
            self.assertIn(b"Management sign in", body)
            self.assertIn(b"caseStatusChips", body)
            self.assertIn(b"caseAssignmentChips", body)
            self.assertIn(b"userRoleChips", body)

    def test_role_filtered_cases_and_patient_matching(self):
        doctor = self.login("doctor", "doctor123")
        agent = self.login("agent", "agent123")
        doctor_cases = self.request("GET", "/cases", token=doctor)["cases"]
        agent_cases = self.request("GET", "/cases", token=agent)["cases"]
        self.assertGreater(len(doctor_cases), len(agent_cases))
        matches = self.request("GET", f"/patients/matches?name={quote('Çolak Ayhan')}", token=agent)["matches"]
        self.assertEqual("Ayhan Çolak", matches[0]["name"])
        self.assertTrue(matches[0]["createdByAnotherAgent"])

    def test_agent_create_doctor_response_and_agent_close(self):
        doctor = self.login("doctor", "doctor123")
        agent = self.login("agent", "agent123")
        created = self.request("POST", "/cases", {
            "patientName": "Test Patient", "grafts": "2500", "currency": "EUR",
            "price": "2400", "note": "Test consultation", "photoCount": 2,
        }, token=agent, expected=201)["case"]
        self.assertEqual("waiting", created["status"])
        answered = self.request("POST", f"/cases/{created['id']}/recommendations", {
            "approximateGrafts": "2400-2600", "recommendedPrice": "EUR 2500", "text": "Suitable donor area."
        }, token=doctor)["case"]
        self.assertEqual("answered", answered["status"])
        self.assertEqual("doctor-emre", answered["assignedDoctorID"])
        closed = self.request("POST", f"/cases/{created['id']}/close", {}, token=agent)["case"]
        self.assertEqual("closed", closed["status"])

    def test_authenticated_photo_download(self):
        agent = self.login("agent", "agent123")
        created = self.request("POST", "/cases", {
            "patientName": "Photo Test Patient", "grafts": "2100", "currency": "EUR",
            "price": "2200", "note": "Photo delivery test", "photoCount": 0,
        }, token=agent, expected=201)["case"]
        photo_body = b"demo-jpeg-body"
        upload = Request(
            self.base + f"/cases/{created['id']}/photos",
            data=photo_body,
            headers={"Authorization": f"Bearer {agent}", "Content-Type": "image/jpeg"},
            method="POST",
        )
        with urlopen(upload) as response:
            uploaded = json.load(response)["case"]
        photo_id = uploaded["photoIDs"][0]

        download = Request(
            self.base + f"/photos/{photo_id}",
            headers={"Authorization": f"Bearer {agent}"},
            method="GET",
        )
        with urlopen(download) as response:
            self.assertEqual("image/jpeg", response.headers.get_content_type())
            self.assertEqual(photo_body, response.read())
        missing_auth = self.request("GET", f"/photos/{photo_id}", expected=401)
        self.assertEqual("authentication_required", missing_auth["error"]["code"])

    def test_duplicate_requires_explicit_decision(self):
        agent = self.login("agent", "agent123")
        payload = {"patientName": "Daniel Morris", "grafts": "2500", "currency": "EUR",
                   "price": "2400", "note": "Repeat", "photoCount": 2}
        conflict = self.request("POST", "/cases", payload, token=agent, expected=409)
        self.assertEqual("duplicate_confirmation_required", conflict["error"]["code"])
        payload["duplicateConfirmedDifferent"] = True
        created = self.request("POST", "/cases", payload, token=agent, expected=201)["case"]
        self.assertNotEqual("PT-1042", created["patient"]["id"])

    def test_agent_cannot_change_another_agents_case(self):
        agent = self.login("agent", "agent123")
        doctor = self.login("doctor", "doctor123")
        cases = self.request("GET", "/cases", token=doctor)["cases"]
        foreign = next(item for item in cases if item["agentName"] == "Mert Demir")
        result = self.request("PATCH", f"/cases/{foreign['id']}/agent-values",
                              {"patientName": foreign["patient"]["name"], "grafts": "1", "currency": "EUR", "price": "1"},
                              token=agent, expected=403)
        self.assertEqual("forbidden", result["error"]["code"])

    def test_admin_user_lifecycle_and_role_protection(self):
        doctor = self.login("doctor", "doctor123")
        forbidden = self.request("GET", "/admin/users", token=doctor, expected=403)
        self.assertEqual("forbidden", forbidden["error"]["code"])

        admin = self.login("admin", "admin123")
        agency_name = "Agency " + uuid.uuid4().hex[:6]
        agency = self.request("POST", "/admin/agencies", {"name": agency_name}, token=admin, expected=201)["agency"]
        username = "test-" + uuid.uuid4().hex[:8]
        created = self.request("POST", "/admin/users", {
            "username": username, "displayName": "Test Agent", "role": "agent",
            "agencyID": agency["id"], "password": "Temporary!123"
        }, token=admin, expected=201)["user"]
        self.assertTrue(created["active"])
        self.assertEqual(agency_name, created["agencyName"])
        new_user_token = self.login(username, "Temporary!123")
        deactivated = self.request("PATCH", f"/admin/users/{created['id']}", {"active": False}, token=admin)["user"]
        self.assertFalse(deactivated["active"])
        expired = self.request("GET", "/cases", token=new_user_token, expected=401)
        self.assertEqual("invalid_session", expired["error"]["code"])
        deleted = self.request("DELETE", f"/admin/users/{created['id']}", token=admin)["user"]
        self.assertTrue(deleted["deleted"])

        history_username = "history-" + uuid.uuid4().hex[:8]
        history_user = self.request("POST", "/admin/users", {
            "username": history_username, "displayName": "History Agent", "role": "agent",
            "agencyID": agency["id"], "password": "Temporary!456"
        }, token=admin, expected=201)["user"]
        history_token = self.login(history_username, "Temporary!456")
        self.request("POST", "/cases", {
            "patientName": "History Patient", "grafts": "2000", "currency": "EUR",
            "price": "2000", "note": "History protection test", "photoCount": 2,
        }, token=history_token, expected=201)
        self.request("PATCH", f"/admin/users/{history_user['id']}", {"active": False}, token=admin)
        protected = self.request("DELETE", f"/admin/users/{history_user['id']}", token=admin, expected=409)
        self.assertEqual("user_has_history", protected["error"]["code"])

    def test_admin_case_table_and_doctor_assignment(self):
        admin = self.login("admin", "admin123")
        cases = self.request("GET", "/admin/cases", token=admin)["cases"]
        self.assertGreater(len(cases), 0)
        target = next(item for item in cases if item["doctorID"] is None)
        result = self.request("PATCH", f"/admin/patients/{target['patientID']}", {
            "doctorID": "doctor-emre", "reason": "Initial administrative assignment"
        }, token=admin)["assignment"]
        self.assertEqual("doctor-emre", result["doctorID"])
        updated = self.request("GET", "/admin/cases", token=admin)["cases"]
        self.assertTrue(all(item["doctorID"] == "doctor-emre" for item in updated if item["patientID"] == target["patientID"]))

    def test_manager_has_oversight_and_only_assignment_write_access(self):
        manager = self.login("manager", "manager123")
        self.assertGreater(len(self.request("GET", "/admin/users", token=manager)["users"]), 0)
        self.assertGreater(len(self.request("GET", "/admin/agencies", token=manager)["agencies"]), 0)
        cases = self.request("GET", "/admin/cases", token=manager)["cases"]
        self.assertGreater(len(cases), 0)

        target = cases[0]
        doctor_id = None if target["doctorID"] else "doctor-emre"
        assignment = self.request("PATCH", f"/admin/patients/{target['patientID']}", {
            "doctorID": doctor_id, "reason": "Manager workload review"
        }, token=manager)["assignment"]
        self.assertEqual(doctor_id, assignment["doctorID"])

        created = self.request("POST", "/admin/users", {
            "username": "blocked-manager-create", "displayName": "Blocked User",
            "role": "agent", "agencyID": "agency-drascom", "password": "Temporary!123"
        }, token=manager, expected=403)
        self.assertEqual("forbidden", created["error"]["code"])
        self.request("POST", "/admin/agencies", {"name": "Blocked Agency"}, token=manager, expected=403)

        other = next(user for user in self.request("GET", "/admin/users", token=manager)["users"] if user["id"] != "manager-local")
        self.request("PATCH", f"/admin/users/{other['id']}", {"active": False}, token=manager, expected=403)
        self.request("DELETE", f"/admin/users/{other['id']}", token=manager, expected=403)

    def test_existing_user_table_migrates_manager_role_constraint(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            database_path = root / "legacy.sqlite3"
            salt, digest = hash_password("Temporary!123")
            with sqlite3.connect(database_path) as connection:
                connection.executescript("""
                    CREATE TABLE agencies (
                      id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                      active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL
                    );
                    CREATE TABLE users (
                      id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE,
                      display_name TEXT NOT NULL,
                      role TEXT NOT NULL CHECK(role IN ('doctor','agent','admin')),
                      password_salt TEXT NOT NULL, password_hash TEXT NOT NULL,
                      agency_id TEXT REFERENCES agencies(id), email TEXT, phone TEXT,
                      active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL
                    );
                    CREATE TABLE sessions (
                      token_hash TEXT PRIMARY KEY,
                      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                      created_at TEXT NOT NULL, expires_at TEXT NOT NULL
                    );
                """)
                connection.execute(
                    "INSERT INTO users VALUES (?,?,?,?,?,?,NULL,NULL,NULL,1,?)",
                    ("legacy-admin", "legacy", "Legacy Admin", "admin", salt, digest, "2026-08-10T00:00:00Z"),
                )
                connection.execute(
                    "INSERT INTO sessions VALUES (?,?,?,?)",
                    ("legacy-session", "legacy-admin", "2026-08-10T00:00:00Z", "2026-08-11T00:00:00Z"),
                )

            Database(database_path, root / "media").initialize(seed=False)
            with sqlite3.connect(database_path) as connection:
                schema = connection.execute(
                    "SELECT sql FROM sqlite_master WHERE type='table' AND name='users'"
                ).fetchone()[0]
                self.assertIn("'manager'", schema)
                self.assertEqual("Legacy Admin", connection.execute(
                    "SELECT display_name FROM users WHERE id='legacy-admin'"
                ).fetchone()[0])
                self.assertEqual("legacy-admin", connection.execute(
                    "SELECT user_id FROM sessions WHERE token_hash='legacy-session'"
                ).fetchone()[0])
                connection.execute(
                    "INSERT INTO users VALUES (?,?,?,?,?,?,NULL,NULL,NULL,1,?)",
                    ("manager-test", "manager-test", "Manager Test", "manager", salt, digest, "2026-08-10T00:00:00Z"),
                )
                self.assertEqual([], connection.execute("PRAGMA foreign_key_check").fetchall())


if __name__ == "__main__":
    unittest.main()
