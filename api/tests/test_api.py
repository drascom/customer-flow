import json
import os
import tempfile
import threading
import unittest
import uuid
from datetime import date
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

from app import create_server


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

    def request(self, method, path, payload=None, token=None, expected=200, extra_headers=None):
        body = None if payload is None else json.dumps(payload).encode()
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if extra_headers:
            headers.update(extra_headers)
        request = Request(self.base + path, data=body, headers=headers, method=method)
        try:
            with urlopen(request) as response:
                self.assertEqual(expected, response.status)
                return json.load(response)
        except HTTPError as error:
            self.assertEqual(expected, error.code)
            return json.load(error)

    def raw_request(
        self, method, path, body=None, content_type=None, token=None, expected=200,
        extra_headers=None,
    ):
        headers = {}
        if content_type:
            headers["Content-Type"] = content_type
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if extra_headers:
            headers.update(extra_headers)
        request = Request(self.base + path, data=body, headers=headers, method=method)
        try:
            with urlopen(request) as response:
                self.assertEqual(expected, response.status)
                return response.read(), response.headers
        except HTTPError as error:
            self.assertEqual(expected, error.code)
            return error.read(), error.headers

    def login(self, username, password):
        return self.request("POST", "/auth/login", {"username": username, "password": password})["token"]

    def test_health_and_login(self):
        health = self.request("GET", "/health")
        self.assertEqual("ok", health["status"])
        self.assertIn("live-updates", health["capabilities"])
        self.assertIn("patient-profile", health["capabilities"])
        self.assertIn("agency-scoping", health["capabilities"])
        self.assertIn("idempotent-writes", health["capabilities"])
        self.assertIn("agency-mcp", health["capabilities"])
        result = self.request("POST", "/auth/login", {"username": "doctor1", "password": "demo123"})
        self.assertEqual("doctor", result["user"]["role"])

    def test_public_mcp_path_proxies_only_to_loopback_service(self):
        received = {}

        class MCPStub(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                size = int(self.headers.get("Content-Length", "0"))
                received.update({
                    "path": self.path,
                    "authorization": self.headers.get("Authorization"),
                    "protocol": self.headers.get("MCP-Protocol-Version"),
                    "body": self.rfile.read(size),
                })
                payload = b'{"jsonrpc":"2.0","result":{"ok":true},"id":1}'
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("MCP-Session-Id", "test-session")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, _format, *_args):
                return

        upstream = ThreadingHTTPServer(("127.0.0.1", 0), MCPStub)
        thread = threading.Thread(target=upstream.serve_forever, daemon=True)
        thread.start()
        previous = os.environ.get("CF_MCP_UPSTREAM_URL")
        os.environ["CF_MCP_UPSTREAM_URL"] = f"http://127.0.0.1:{upstream.server_port}/mcp"
        try:
            origin = self.base.removesuffix("/api/v1")
            request = Request(
                origin + "/mcp?trace=1",
                data=b"{}",
                headers={
                    "Authorization": "Bearer cfmcp_test-token",
                    "Content-Type": "application/json",
                    "MCP-Protocol-Version": "2025-11-25",
                },
                method="POST",
            )
            with urlopen(request) as response:
                self.assertEqual(200, response.status)
                self.assertEqual("test-session", response.headers["MCP-Session-Id"])
                self.assertTrue(json.load(response)["result"]["ok"])
            self.assertEqual("/mcp?trace=1", received["path"])
            self.assertEqual("Bearer cfmcp_test-token", received["authorization"])
            self.assertEqual("2025-11-25", received["protocol"])
            self.assertEqual(b"{}", received["body"])
        finally:
            if previous is None:
                os.environ.pop("CF_MCP_UPSTREAM_URL", None)
            else:
                os.environ["CF_MCP_UPSTREAM_URL"] = previous
            upstream.shutdown()
            upstream.server_close()

    def test_agency_mcp_token_is_admin_only_hashed_and_rotation_invalidates_old_token(self):
        admin = self.login("admin", "demo123")
        manager = self.login("manager", "demo123")
        agent = self.login("user1", "demo123")
        agency = self.request(
            "POST", "/admin/agencies", {"name": "MCP Test " + uuid.uuid4().hex[:8]},
            token=admin, expected=201,
        )["agency"]

        self.request("GET", f"/admin/agencies/{agency['id']}/mcp", token=manager, expected=403)
        self.request(
            "POST", f"/admin/agencies/{agency['id']}/mcp/rotate", {}, token=agent, expected=403
        )
        first = self.request(
            "POST", f"/admin/agencies/{agency['id']}/mcp/rotate", {}, token=admin
        )["connection"]
        self.assertTrue(first["configured"])
        self.assertEqual("https://flow.drascom.uk/mcp", first["endpointURL"])
        self.assertTrue(first["accessToken"].startswith("cfmcp_"))

        with self.server.database.connect() as conn:
            stored = conn.execute(
                "SELECT token_hash,service_user_id FROM agency_mcp_credentials WHERE agency_id=?",
                (agency["id"],),
            ).fetchone()
            self.assertNotEqual(first["accessToken"], stored["token_hash"])
            self.assertNotIn(first["accessToken"], self.server.database.path.read_bytes().decode("latin-1"))
            first_service_user = stored["service_user_id"]
        principal = self.server.database.authenticate_mcp_token(first["accessToken"])
        self.assertEqual(agency["id"], principal["agencyID"])

        second = self.request(
            "POST", f"/admin/agencies/{agency['id']}/mcp/rotate", {}, token=admin
        )["connection"]
        self.assertNotEqual(first["accessToken"], second["accessToken"])
        with self.assertRaises(Exception):
            self.server.database.authenticate_mcp_token(first["accessToken"])
        current = self.server.database.authenticate_mcp_token(second["accessToken"])
        self.assertEqual(first_service_user, current["serviceUserID"])
        info = self.request("GET", f"/admin/agencies/{agency['id']}/mcp", token=admin)["connection"]
        self.assertNotIn("accessToken", info)

    def test_mcp_bearer_has_narrow_api_scope_and_writes_publish_live_events(self):
        admin = self.login("admin", "demo123")
        agency = self.request(
            "POST", "/admin/agencies", {"name": "MCP Events " + uuid.uuid4().hex[:8]},
            token=admin, expected=201,
        )["agency"]
        mcp_token = self.request(
            "POST", f"/admin/agencies/{agency['id']}/mcp/rotate", {}, token=admin
        )["connection"]["accessToken"]

        identity = self.request("GET", "/auth/me", token=mcp_token)["user"]
        self.assertEqual("agent", identity["role"])
        self.assertEqual(agency["id"], identity["agencyID"])
        self.assertEqual([], self.request("GET", "/cases", token=mcp_token)["cases"])

        for method, path, payload in (
            ("GET", "/events?since=-1", None),
            ("GET", "/admin/cases", None),
            ("PATCH", "/auth/profile", {"displayName": "Not allowed"}),
            ("POST", "/auth/logout", {}),
            ("POST", "/auth/password-reset/request", {"username": "admin"}),
        ):
            denied = self.request(method, path, payload, token=mcp_token, expected=403)
            self.assertEqual("mcp_scope_forbidden", denied["error"]["code"])

        revision = self.request("GET", "/events?since=-1", token=admin)["revision"]
        created = self.request(
            "POST", "/cases", {
                "patientName": "MCP Realtime " + uuid.uuid4().hex[:8],
                "grafts": "2200", "currency": "GBP", "price": "2100",
                "note": "Created through the MCP-scoped API", "photoCount": 0,
            }, token=mcp_token, expected=201,
            extra_headers={"Idempotency-Key": "mcp:create:12345678"},
        )["case"]
        event = self.request("GET", f"/events?since={revision}", token=admin)
        self.assertEqual("case.created", event["event"]["kind"])
        self.assertEqual(created["id"], event["event"]["entityID"])

        detail = self.request("GET", f"/cases/{created['id']}", token=mcp_token)["case"]
        self.assertEqual(created["reference"], detail["reference"])
        revision = event["revision"]
        self.request(
            "POST", f"/cases/{created['id']}/agent-updates", {"text": "MCP update"},
            token=mcp_token,
            extra_headers={"Idempotency-Key": "mcp:message:12345678"},
        )
        event = self.request("GET", f"/events?since={revision}", token=admin)
        self.assertEqual("message.created", event["event"]["kind"])

        revision = event["revision"]
        self.raw_request(
            "POST", f"/cases/{created['id']}/photos", body=b"\xff\xd8\xffmcp-photo",
            content_type="image/jpeg", token=mcp_token, expected=201,
            extra_headers={"Idempotency-Key": "mcp:photo:12345678"},
        )
        event = self.request("GET", f"/events?since={revision}", token=admin)
        self.assertEqual("photo.created", event["event"]["kind"])

        denied = self.request(
            "POST", f"/cases/{created['id']}/close", {}, token=mcp_token, expected=403
        )
        self.assertEqual("mcp_scope_forbidden", denied["error"]["code"])

    def test_optional_patient_profile_round_trips_and_updates(self):
        agent = self.login("user1", "demo123")
        admin = self.login("admin", "demo123")
        birth_date = "1990-04-20"
        today = date.today()
        expected_age = today.year - 1990 - ((today.month, today.day) < (4, 20))

        created = self.request("POST", "/cases", {
            "patientName": "Profile Patient " + uuid.uuid4().hex[:6],
            "grafts": "2400", "currency": "GBP", "price": "2300",
            "note": "Patient profile test", "photoCount": 0,
            "patientProfile": {
                "dateOfBirth": birth_date,
                "gender": "female",
                "phone": "+44 7700 900123",
                "email": "patient@example.test",
                "address": "Manchester, Greater Manchester",
                "occupation": "Architect",
                "profileNote": "Prefers afternoon appointments",
            },
        }, token=agent, expected=201)["case"]

        self.assertEqual(birth_date, created["patient"]["dateOfBirth"])
        self.assertEqual(expected_age, created["patient"]["age"])
        self.assertEqual("female", created["patient"]["gender"])
        self.assertEqual("Architect", created["patient"]["occupation"])

        edited = self.request("PATCH", f"/cases/{created['id']}/agent-values", {
            "patientName": created["patient"]["name"],
            "grafts": "2500", "currency": "GBP", "price": "2350",
            "patientProfile": {
                "dateOfBirth": None,
                "age": 41,
                "gender": "prefer_not_to_say",
                "phone": "+44 7700 900999",
                "email": None,
                "address": "Leeds",
                "occupation": "Architect",
                "profileNote": "Contact by phone",
            },
        }, token=agent)["case"]
        self.assertIsNone(edited["patient"]["dateOfBirth"])
        self.assertEqual(41, edited["patient"]["age"])
        self.assertEqual(41, edited["patient"]["statedAge"])
        self.assertEqual("prefer_not_to_say", edited["patient"]["gender"])
        self.assertEqual("+44 7700 900999", edited["patient"]["phone"])
        self.assertIsNone(edited["patient"]["email"])

        admin_case = next(
            item for item in self.request("GET", "/admin/cases", token=admin)["cases"]
            if item["id"] == created["id"]
        )
        self.assertEqual(41, admin_case["age"])
        self.assertEqual(41, admin_case["statedAge"])
        self.assertEqual("Leeds", admin_case["patientAddress"])
        self.assertEqual("Contact by phone", admin_case["profileNote"])

        invalid = self.request("POST", "/cases", {
            "patientName": "Invalid Profile Patient", "grafts": "2000",
            "currency": "GBP", "price": "1800", "note": "Invalid DOB",
            "photoCount": 0,
            "patientProfile": {"dateOfBirth": "2999-01-01"},
        }, token=agent, expected=422)
        self.assertEqual("invalid_date_of_birth", invalid["error"]["code"])

        invalid_age = self.request("POST", "/cases", {
            "patientName": "Invalid Age Patient", "grafts": "2000",
            "currency": "GBP", "price": "1800", "note": "Invalid age",
            "photoCount": 0, "patientProfile": {"age": 131},
        }, token=agent, expected=422)
        self.assertEqual("invalid_patient_age", invalid_age["error"]["code"])

    def test_authenticated_clients_receive_live_change_events(self):
        admin = self.login("admin", "demo123")
        agent = self.login("user1", "demo123")
        current = self.request("GET", "/events?since=-1", token=admin)

        created = self.request("POST", "/cases", {
            "patientName": "Live Event Patient " + uuid.uuid4().hex[:6],
            "grafts": "2200", "currency": "GBP", "price": "2100",
            "note": "Live update test", "photoCount": 0,
        }, token=agent, expected=201)["case"]

        update = self.request("GET", f"/events?since={current['revision']}", token=admin)
        self.assertTrue(update["changed"])
        self.assertGreater(update["revision"], current["revision"])
        self.assertEqual("case.created", update["event"]["kind"])
        self.assertEqual(created["id"], update["event"]["entityID"])
        self.request("GET", "/events?since=-1", expected=401)

    def test_logout_consumes_body_before_next_login_on_same_connection(self):
        connection = HTTPConnection("127.0.0.1", self.server.server_port)
        try:
            login_body = json.dumps({"username": "manager", "password": "demo123"})
            connection.request("POST", "/api/v1/auth/login", login_body, {"Content-Type": "application/json"})
            login_response = connection.getresponse()
            self.assertEqual(200, login_response.status)
            token = json.loads(login_response.read())["token"]

            connection.request(
                "POST",
                "/api/v1/auth/logout",
                "{}",
                {"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
            )
            logout_response = connection.getresponse()
            self.assertEqual(200, logout_response.status)
            logout_response.read()

            connection.request("POST", "/api/v1/auth/login", login_body, {"Content-Type": "application/json"})
            second_login = connection.getresponse()
            self.assertEqual(200, second_login.status)
            self.assertEqual("manager", json.loads(second_login.read())["user"]["role"])
        finally:
            connection.close()

    def test_profile_password_change_and_forgotten_password(self):
        admin = self.login("admin", "demo123")
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
        doctor = self.login("doctor1", "demo123")
        agent = self.login("user2", "demo123")
        doctor_cases = self.request("GET", "/cases", token=doctor)["cases"]
        agent_cases = self.request("GET", "/cases", token=agent)["cases"]
        self.assertGreater(len(doctor_cases), len(agent_cases))
        self.assertTrue(agent_cases)
        self.assertTrue(all(item["agencyName"] == "Acenta 2" for item in agent_cases))
        matches = self.request("GET", f"/patients/matches?name={quote('Çolak Ayhan')}", token=agent)["matches"]
        self.assertEqual("Ayhan Çolak", matches[0]["name"])
        self.assertFalse(matches[0]["createdByAnotherAgent"])

    def test_patient_matching_and_existing_patient_link_are_agency_scoped(self):
        agent_one = self.login("user1", "demo123")
        agent_two = self.login("user2", "demo123")
        unique_name = "Agency Boundary " + uuid.uuid4().hex[:8]
        first = self.request("POST", "/cases", {
            "patientName": unique_name,
            "grafts": "2100", "currency": "GBP", "price": "2000",
            "note": "Agency one confidential case", "photoCount": 0,
        }, token=agent_one, expected=201)["case"]

        self.assertEqual([], self.request(
            "GET", f"/patients/matches?name={quote(unique_name)}", token=agent_two
        )["matches"])
        denied = self.request("POST", "/cases", {
            "patientName": unique_name,
            "grafts": "2200", "currency": "GBP", "price": "2100",
            "note": "Attempt to link another agency patient", "photoCount": 0,
            "existingPatientID": first["patient"]["id"],
        }, token=agent_two, expected=404)
        self.assertEqual("patient_not_found", denied["error"]["code"])

        second = self.request("POST", "/cases", {
            "patientName": unique_name,
            "grafts": "2200", "currency": "GBP", "price": "2100",
            "note": "Independent agency two patient", "photoCount": 0,
        }, token=agent_two, expected=201)["case"]
        self.assertNotEqual(first["patient"]["id"], second["patient"]["id"])
        matches = self.request(
            "GET", f"/patients/matches?name={quote(unique_name)}", token=agent_two
        )["matches"]
        self.assertEqual([second["patient"]["id"]], [item["id"] for item in matches])

    def test_idempotency_keys_deduplicate_case_message_and_photo_writes(self):
        agent = self.login("user1", "demo123")
        payload = {
            "patientName": "Idempotent Patient " + uuid.uuid4().hex[:8],
            "grafts": "2300", "currency": "GBP", "price": "2200",
            "note": "Created exactly once", "photoCount": 0,
        }
        create_key = "case:create:" + uuid.uuid4().hex
        first = self.request(
            "POST", "/cases", payload, token=agent, expected=201,
            extra_headers={"Idempotency-Key": create_key},
        )["case"]
        replay = self.request(
            "POST", "/cases", payload, token=agent, expected=201,
            extra_headers={"Idempotency-Key": create_key},
        )["case"]
        self.assertEqual(first["id"], replay["id"])

        changed_payload = dict(payload, note="A different request")
        conflict = self.request(
            "POST", "/cases", changed_payload, token=agent, expected=409,
            extra_headers={"Idempotency-Key": create_key},
        )
        self.assertEqual("idempotency_conflict", conflict["error"]["code"])

        message_key = "message:add:" + uuid.uuid4().hex
        message_payload = {"text": "Send this update once"}
        updated = self.request(
            "POST", f"/cases/{first['id']}/agent-updates", message_payload,
            token=agent, extra_headers={"Idempotency-Key": message_key},
        )["case"]
        replayed_update = self.request(
            "POST", f"/cases/{first['id']}/agent-updates", message_payload,
            token=agent, extra_headers={"Idempotency-Key": message_key},
        )["case"]
        self.assertEqual(len(updated["messages"]), len(replayed_update["messages"]))

        photo_key = "photo:add:" + uuid.uuid4().hex
        photo = b"\xff\xd8\xffidempotent-photo\xff\xd9"
        body, _ = self.raw_request(
            "POST", f"/cases/{first['id']}/photos", body=photo,
            content_type="image/jpeg", token=agent, expected=201,
            extra_headers={"Idempotency-Key": photo_key},
        )
        body_replay, _ = self.raw_request(
            "POST", f"/cases/{first['id']}/photos", body=photo,
            content_type="image/jpeg", token=agent, expected=201,
            extra_headers={"Idempotency-Key": photo_key},
        )
        uploaded = json.loads(body)["case"]
        uploaded_replay = json.loads(body_replay)["case"]
        self.assertEqual(uploaded["photoIDs"], uploaded_replay["photoIDs"])
        self.assertEqual(1, uploaded_replay["photoCount"])

        invalid = self.request(
            "POST", f"/cases/{first['id']}/agent-updates", {"text": "Invalid key"},
            token=agent, expected=422, extra_headers={"Idempotency-Key": "short"},
        )
        self.assertEqual("invalid_idempotency_key", invalid["error"]["code"])

    def test_doctors_can_view_every_case_but_cannot_change_another_doctors_case(self):
        doctor = self.login("doctor1", "demo123")
        other_doctor = self.login("doctor2", "demo123")
        agent = self.login("user1", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Shared Doctor View", "grafts": "2200", "currency": "GBP",
            "price": "2100", "note": "Visible to every doctor", "photoCount": 1,
        }, token=agent, expected=201)["case"]
        photo = b"\xff\xd8shared-doctor-photo\xff\xd9"
        uploaded_body, _ = self.raw_request(
            "POST", f"/cases/{created['id']}/photos", body=photo,
            content_type="image/jpeg", token=agent, expected=201,
        )
        photo_id = json.loads(uploaded_body)["case"]["photoIDs"][0]
        self.request("POST", f"/cases/{created['id']}/doctor-messages", {
            "text": "Claimed by the second doctor",
        }, token=other_doctor)

        visible_cases = self.request("GET", "/cases", token=doctor)["cases"]
        self.assertTrue(any(item["id"] == created["id"] for item in visible_cases))
        self.assertEqual(created["id"], self.request(
            "GET", f"/cases/{created['id']}", token=doctor,
        )["case"]["id"])
        self.assertEqual(photo, self.raw_request("GET", f"/photos/{photo_id}", token=doctor)[0])
        blocked = self.request("POST", f"/cases/{created['id']}/doctor-messages", {
            "text": "Should not overwrite the assigned doctor",
        }, token=doctor, expected=409)
        self.assertEqual("case_changed", blocked["error"]["code"])

    def test_agent_create_doctor_response_and_agent_close(self):
        doctor = self.login("doctor1", "demo123")
        agent = self.login("user1", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Test Patient", "grafts": "2500", "currency": "GBP",
            "price": "2400", "note": "Test consultation", "photoCount": 2,
        }, token=agent, expected=201)["case"]
        self.assertEqual("waiting", created["status"])
        self.assertEqual("GBP", created["currency"])
        answered = self.request("POST", f"/cases/{created['id']}/recommendations", {
            "approximateGrafts": "2400-2600", "recommendedPrice": "£2500", "text": "Suitable donor area."
        }, token=doctor)["case"]
        self.assertEqual("answered", answered["status"])
        self.assertEqual("doctor-emre", answered["assignedDoctorID"])
        doctor_message = next(message for message in answered["messages"] if message["role"] == "doctor")
        self.assertEqual("£2500", doctor_message["recommendedPrice"])
        missing = self.request("POST", f"/cases/{created['id']}/close", {}, token=agent, expected=422)
        self.assertEqual("final_plan_required", missing["error"]["code"])
        closed = self.request("POST", f"/cases/{created['id']}/close", {
            "finalGrafts": "2550", "finalPrice": "2450",
        }, token=agent)["case"]
        self.assertEqual("closed", closed["status"])
        self.assertEqual("2550", closed["finalGrafts"])
        self.assertEqual("2450", closed["finalPrice"])
        self.assertIsNotNone(closed["finalizedAt"])
        self.assertTrue(any(
            message["role"] == "system" and "2550 grafts" in message["text"]
            for message in closed["messages"]
        ))

    def test_doctor_and_agent_can_exchange_multiple_messages_with_optional_plan_fields(self):
        doctor = self.login("doctor1", "demo123")
        agent = self.login("user1", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Conversation Test", "grafts": "2000", "currency": "GBP",
            "price": "1900", "note": "Continuous conversation test", "photoCount": 0,
        }, token=agent, expected=201)["case"]

        first_reply = self.request("POST", f"/cases/{created['id']}/doctor-messages", {
            "text": "Could you upload another donor-area photo?",
        }, token=doctor)["case"]
        self.assertEqual("answered", first_reply["status"])
        first_message = next(
            message for message in first_reply["messages"]
            if message["text"] == "Could you upload another donor-area photo?"
        )
        self.assertIsNone(first_message["approximateGrafts"])
        self.assertIsNone(first_message["recommendedPrice"])

        second_reply = self.request("POST", f"/cases/{created['id']}/doctor-messages", {
            "text": "A front-facing photo would also be useful.",
        }, token=doctor)["case"]
        doctor_messages = [message for message in second_reply["messages"] if message["role"] == "doctor"]
        self.assertEqual(2, len(doctor_messages))

        agent_reply = self.request("POST", f"/cases/{created['id']}/agent-updates", {
            "text": "I will upload both photos now.",
        }, token=agent)["case"]
        self.assertEqual("waiting", agent_reply["status"])

        plan_reply = self.request("POST", f"/cases/{created['id']}/doctor-messages", {
            "text": "The graft range can remain conservative.",
            "approximateGrafts": "2100-2300",
        }, token=doctor)["case"]
        self.assertEqual("answered", plan_reply["status"])
        latest_message = plan_reply["messages"][-1]
        self.assertEqual("2100-2300", latest_message["approximateGrafts"])
        self.assertIsNone(latest_message["recommendedPrice"])

    def test_agent_uploads_and_authorized_users_fetch_real_photo(self):
        doctor = self.login("doctor1", "demo123")
        agent = self.login("user1", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Photo Test Patient", "grafts": "2200", "currency": "GBP",
            "price": "2100", "note": "Real photo upload test", "photoCount": 2,
        }, token=agent, expected=201)["case"]
        self.assertEqual(0, created["photoCount"])
        self.assertEqual([], created["photoIDs"])

        jpeg = b"\xff\xd8customer-flow-test-photo\xff\xd9"
        uploaded_body, _ = self.raw_request(
            "POST", f"/cases/{created['id']}/photos", body=jpeg,
            content_type="image/jpeg", token=agent, expected=201,
        )
        uploaded = json.loads(uploaded_body)["case"]
        self.assertEqual(1, uploaded["photoCount"])
        self.assertEqual(1, len(uploaded["photoIDs"]))
        photo_id = uploaded["photoIDs"][0]

        photo_body, photo_headers = self.raw_request(
            "GET", f"/photos/{photo_id}", token=doctor,
        )
        self.assertEqual(jpeg, photo_body)
        self.assertEqual("image/jpeg", photo_headers.get_content_type())
        self.raw_request("GET", f"/photos/{photo_id}", expected=401)

    def test_case_edits_and_photo_uploads_accept_uppercase_uuid_paths(self):
        agent = self.login("user1", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Uppercase UUID Patient", "grafts": "2100", "currency": "GBP",
            "price": "2000", "note": "UUID path compatibility test", "photoCount": 1,
        }, token=agent, expected=201)["case"]
        uppercase_id = created["id"].upper()

        edited = self.request("PATCH", f"/cases/{uppercase_id}/agent-values", {
            "patientName": "Uppercase UUID Patient", "grafts": "2300",
            "currency": "GBP", "price": "2200",
        }, token=agent)["case"]
        self.assertEqual("2300", edited["agentGrafts"])

        uploaded_body, _ = self.raw_request(
            "POST", f"/cases/{uppercase_id}/photos", body=b"\xff\xd8uppercase-uuid\xff\xd9",
            content_type="image/jpeg", token=agent, expected=201,
        )
        self.assertEqual(created["id"], json.loads(uploaded_body)["case"]["id"])

    def test_agent_photo_removal_is_soft_deleted_and_admin_visible(self):
        agent = self.login("user1", "demo123")
        other_agent = self.login("user2", "demo123")
        doctor = self.login("doctor1", "demo123")
        admin = self.login("admin", "demo123")
        manager = self.login("manager", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Soft Delete Patient", "grafts": "2000", "currency": "GBP",
            "price": "1900", "note": "Photo retention test", "photoCount": 1,
        }, token=agent, expected=201)["case"]
        photo = b"\xff\xd8retained-soft-delete-photo\xff\xd9"
        uploaded_body, _ = self.raw_request(
            "POST", f"/cases/{created['id'].upper()}/photos", body=photo,
            content_type="image/jpeg", token=agent, expected=201,
        )
        uploaded = json.loads(uploaded_body)["case"]
        photo_id = uploaded["photoIDs"][0]
        self.assertEqual(photo, self.raw_request("GET", f"/photos/{photo_id}", token=doctor)[0])
        self.request("DELETE", f"/admin/photos/{photo_id}", {}, token=admin, expected=409)

        blocked = self.request(
            "DELETE", f"/cases/{created['id'].upper()}/photos/{photo_id}", {},
            token=other_agent, expected=403,
        )
        self.assertEqual("forbidden", blocked["error"]["code"])

        removed = self.request(
            "DELETE", f"/cases/{created['id'].upper()}/photos/{photo_id}", {}, token=agent,
        )["case"]
        self.assertEqual(0, removed["photoCount"])
        self.assertEqual([], removed["photoIDs"])
        self.raw_request("GET", f"/photos/{photo_id}", token=agent, expected=404)
        self.raw_request("GET", f"/photos/{photo_id}", token=doctor, expected=404)

        admin_case = next(
            item for item in self.request("GET", "/admin/cases", token=admin)["cases"]
            if item["id"] == created["id"]
        )
        deleted_photo = next(item for item in admin_case["photos"] if item["id"] == photo_id)
        self.assertTrue(deleted_photo["deleted"])
        self.assertEqual("Selin Arslan", deleted_photo["deletedByName"])
        self.assertEqual(1, admin_case["deletedPhotoCount"])
        self.assertEqual(photo, self.raw_request("GET", f"/photos/{photo_id}", token=admin)[0])
        self.request("DELETE", f"/admin/photos/{photo_id}", {}, token=manager, expected=403)
        purged = self.request("DELETE", f"/admin/photos/{photo_id}", {}, token=admin)["photo"]
        self.assertTrue(purged["purged"])
        self.raw_request("GET", f"/photos/{photo_id}", token=admin, expected=404)
        refreshed = next(
            item for item in self.request("GET", "/admin/cases", token=admin)["cases"]
            if item["id"] == created["id"]
        )
        self.assertFalse(any(item["id"] == photo_id for item in refreshed["photos"]))

    def test_agents_and_doctors_soft_delete_only_their_own_messages(self):
        agent = self.login("user1", "demo123")
        other_agent = self.login("user2", "demo123")
        doctor = self.login("doctor1", "demo123")
        admin = self.login("admin", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Message Retention Patient", "grafts": "2100", "currency": "GBP",
            "price": "2050", "note": "Message retention test", "photoCount": 2,
        }, token=agent, expected=201)["case"]

        updated = self.request(
            "POST", f"/cases/{created['id']}/agent-updates", {"text": "Please review this update"},
            token=agent,
        )["case"]
        agent_message = next(message for message in updated["messages"] if message["text"] == "Please review this update")
        self.request(
            "DELETE", f"/cases/{created['id']}/messages/{agent_message['id']}", {},
            token=other_agent, expected=403,
        )
        self.request(
            "DELETE", f"/cases/{created['id']}/messages/{agent_message['id']}", {},
            token=doctor, expected=403,
        )
        after_agent_delete = self.request(
            "DELETE", f"/cases/{created['id']}/messages/{agent_message['id'].upper()}", {}, token=agent,
        )["case"]
        self.assertFalse(any(message["id"] == agent_message["id"] for message in after_agent_delete["messages"]))

        answered = self.request(
            "POST", f"/cases/{created['id']}/recommendations",
            {"approximateGrafts": "2150", "recommendedPrice": "£2200", "text": "Doctor reply"},
            token=doctor,
        )["case"]
        doctor_message = next(message for message in answered["messages"] if message["text"] == "Doctor reply")
        self.request(
            "DELETE", f"/cases/{created['id']}/messages/{doctor_message['id']}", {},
            token=agent, expected=403,
        )
        after_doctor_delete = self.request(
            "DELETE", f"/cases/{created['id']}/messages/{doctor_message['id']}", {}, token=doctor,
        )["case"]
        self.assertEqual("waiting", after_doctor_delete["status"])
        self.assertFalse(any(message["id"] == doctor_message["id"] for message in after_doctor_delete["messages"]))

        admin_case = next(
            item for item in self.request("GET", "/admin/cases", token=admin)["cases"]
            if item["id"] == created["id"]
        )
        self.assertEqual(2, admin_case["deletedMessageCount"])
        deleted_ids = {message["id"] for message in admin_case["messages"] if message["deletedAt"]}
        self.assertEqual({agent_message["id"], doctor_message["id"]}, deleted_ids)

    def test_quick_look_edit_is_saved_as_a_photo_message(self):
        agent = self.login("user1", "demo123")
        other_agent = self.login("user2", "demo123")
        doctor = self.login("doctor1", "demo123")
        admin = self.login("admin", "demo123")
        manager = self.login("manager", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Markup Message Patient", "grafts": "2000", "currency": "GBP",
            "price": "1900", "note": "Quick Look markup test", "photoCount": 0,
        }, token=agent, expected=201)["case"]

        edited_photo = b"\xff\xd8quick-look-edited-copy\xff\xd9"
        uploaded_body, _ = self.raw_request(
            "POST", f"/cases/{created['id'].upper()}/message-photos", body=edited_photo,
            content_type="image/jpeg", token=doctor, expected=201,
        )
        updated = json.loads(uploaded_body)["case"]
        self.assertEqual("doctor-emre", updated["assignedDoctorID"])
        photo_message = next(message for message in updated["messages"] if message["attachmentPhotoID"])
        self.assertEqual("doctor", photo_message["role"])
        self.assertEqual("Annotated patient photo", photo_message["text"])

        attachment_id = photo_message["attachmentPhotoID"]
        self.assertEqual(
            edited_photo,
            self.raw_request("GET", f"/message-photos/{attachment_id}", token=agent)[0],
        )
        self.raw_request("GET", f"/message-photos/{attachment_id}", token=other_agent, expected=403)

        admin_edit = b"\xff\xd8admin-markup-copy\xff\xd9"
        admin_body, _ = self.raw_request(
            "POST", f"/cases/{created['id']}/message-photos", body=admin_edit,
            content_type="image/jpeg", token=admin, expected=201,
        )
        admin_updated = json.loads(admin_body)["case"]
        admin_message = next(
            message for message in admin_updated["messages"]
            if message["attachmentPhotoID"] and message["role"] == "admin"
        )
        self.assertEqual("admin", admin_message["role"])
        admin_case = next(
            item for item in self.request("GET", "/admin/cases", token=admin)["cases"]
            if item["id"] == created["id"]
        )
        self.assertEqual(admin_message["author"], admin_case["latestMessageAuthor"])
        self.assertEqual(admin_message["text"], admin_case["latestMessageText"])
        self.assertEqual(admin_message["createdAt"], admin_case["latestMessageAt"])
        self.assertTrue(admin_case["latestMessageHasPhoto"])
        self.raw_request(
            "POST", f"/cases/{created['id']}/message-photos", body=admin_edit,
            content_type="image/jpeg", token=manager, expected=403,
        )

    def test_duplicate_requires_explicit_decision(self):
        agent = self.login("user1", "demo123")
        payload = {"patientName": "Daniel Morris", "grafts": "2500", "currency": "GBP",
                   "price": "2400", "note": "Repeat", "photoCount": 2}
        conflict = self.request("POST", "/cases", payload, token=agent, expected=409)
        self.assertEqual("duplicate_confirmation_required", conflict["error"]["code"])
        payload["duplicateConfirmedDifferent"] = True
        created = self.request("POST", "/cases", payload, token=agent, expected=201)["case"]
        self.assertNotEqual("PT-1042", created["patient"]["id"])

    def test_agent_cannot_change_another_agents_case(self):
        agent = self.login("user1", "demo123")
        doctor = self.login("doctor1", "demo123")
        cases = self.request("GET", "/cases", token=doctor)["cases"]
        foreign = next(item for item in cases if item["agentName"] == "Mert Demir")
        result = self.request("PATCH", f"/cases/{foreign['id']}/agent-values",
                              {"patientName": foreign["patient"]["name"], "grafts": "1", "currency": "GBP", "price": "1"},
                              token=agent, expected=403)
        self.assertEqual("forbidden", result["error"]["code"])

    def test_agents_can_view_but_not_edit_cases_from_their_agency(self):
        admin = self.login("admin", "demo123")
        owner = self.login("user1", "demo123")
        agency = next(item for item in self.request("GET", "/admin/agencies", token=admin)["agencies"]
                      if item["name"] == "Acenta 1")
        username = "agency-peer-" + uuid.uuid4().hex[:8]
        peer = self.request("POST", "/admin/users", {
            "username": username, "displayName": "Agency Peer", "role": "agent",
            "agencyID": agency["id"], "password": "Temporary!789",
        }, token=admin, expected=201)["user"]
        peer_token = self.login(username, "Temporary!789")

        created = self.request("POST", "/cases", {
            "patientName": "Shared Agency Patient", "grafts": "2400", "currency": "GBP",
            "price": "2300", "note": "Visible to agency colleagues", "photoCount": 2,
        }, token=owner, expected=201)["case"]

        peer_cases = self.request("GET", "/cases", token=peer_token)["cases"]
        shared = next(item for item in peer_cases if item["id"] == created["id"])
        self.assertEqual("Selin Arslan", shared["agentName"])
        self.assertEqual(created["agentID"], shared["agentID"])
        self.assertEqual(created["id"], self.request(
            "GET", f"/cases/{created['id']}", token=peer_token,
        )["case"]["id"])

        blocked = self.request("PATCH", f"/cases/{created['id']}/agent-values", {
            "patientName": created["patient"]["name"], "grafts": "1", "currency": "GBP", "price": "1",
        }, token=peer_token, expected=403)
        self.assertEqual("forbidden", blocked["error"]["code"])

    def test_admin_user_lifecycle_and_role_protection(self):
        doctor = self.login("doctor1", "demo123")
        forbidden = self.request("GET", "/admin/users", token=doctor, expected=403)
        self.assertEqual("forbidden", forbidden["error"]["code"])

        admin = self.login("admin", "demo123")
        agency_name = "Agency " + uuid.uuid4().hex[:6]
        agency = self.request("POST", "/admin/agencies", {"name": agency_name}, token=admin, expected=201)["agency"]
        agency_name += " Updated"
        agency = self.request("PATCH", f"/admin/agencies/{agency['id']}", {
            "name": agency_name
        }, token=admin)["agency"]
        self.assertEqual(agency_name, agency["name"])
        username = "test-" + uuid.uuid4().hex[:8]
        created = self.request("POST", "/admin/users", {
            "username": username, "displayName": "Test Agent", "role": "agent",
            "agencyID": agency["id"], "password": "Temporary!123"
        }, token=admin, expected=201)["user"]
        self.assertTrue(created["active"])
        self.assertEqual(agency_name, created["agencyName"])
        created = self.request("PATCH", f"/admin/users/{created['id']}", {
            "username": username, "displayName": "Edited Agent", "role": "agent",
            "agencyID": agency["id"]
        }, token=admin)["user"]
        self.assertEqual("Edited Agent", created["displayName"])
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
            "patientName": "History Patient", "grafts": "2000", "currency": "GBP",
            "price": "2000", "note": "History protection test", "photoCount": 2,
        }, token=history_token, expected=201)
        self.request("PATCH", f"/admin/users/{history_user['id']}", {"active": False}, token=admin)
        protected = self.request("DELETE", f"/admin/users/{history_user['id']}", token=admin, expected=409)
        self.assertEqual("user_has_history", protected["error"]["code"])

    def test_admin_case_table_and_doctor_assignment(self):
        admin = self.login("admin", "demo123")
        cases = self.request("GET", "/admin/cases", token=admin)["cases"]
        self.assertGreater(len(cases), 0)
        target = next(item for item in cases if item["doctorID"] is None)
        result = self.request("PATCH", f"/admin/patients/{target['patientID']}", {
            "doctorID": "doctor-emre", "reason": "Initial administrative assignment"
        }, token=admin)["assignment"]
        self.assertEqual("doctor-emre", result["doctorID"])
        updated = self.request("GET", "/admin/cases", token=admin)["cases"]
        self.assertTrue(all(item["doctorID"] == "doctor-emre" for item in updated if item["patientID"] == target["patientID"]))

    def test_only_admin_can_permanently_delete_case_and_all_media(self):
        agent = self.login("user1", "demo123")
        manager = self.login("manager", "demo123")
        admin = self.login("admin", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Delete Test " + uuid.uuid4().hex[:8],
            "grafts": "2100", "currency": "GBP", "price": "2000",
            "note": "Permanent case deletion test", "photoCount": 0,
        }, token=agent, expected=201)["case"]
        case_id = created["id"]
        patient_id = created["patient"]["id"]

        self.raw_request(
            "POST", f"/cases/{case_id}/photos", b"original-photo", "image/jpeg", agent, expected=201
        )
        self.raw_request(
            "POST", f"/cases/{case_id}/message-photos", b"annotated-photo", "image/jpeg", agent, expected=201
        )

        with self.server.database.connect() as conn:
            media_paths = [
                self.server.database.media_root / row[0]
                for row in conn.execute(
                    "SELECT file_path FROM photos WHERE case_id=? AND file_path IS NOT NULL "
                    "UNION ALL SELECT attachment_path FROM messages WHERE case_id=? AND attachment_path IS NOT NULL",
                    (case_id, case_id),
                ).fetchall()
            ]
        self.assertGreaterEqual(len(media_paths), 2)
        self.assertTrue(all(path.is_file() for path in media_paths))

        forbidden = self.request("DELETE", f"/admin/cases/{case_id}", token=manager, expected=403)
        self.assertEqual("forbidden", forbidden["error"]["code"])

        deleted = self.request("DELETE", f"/admin/cases/{case_id}", token=admin)["case"]
        self.assertTrue(deleted["deleted"])
        self.assertTrue(deleted["patientDeleted"])
        self.assertGreaterEqual(deleted["photoCount"], 1)
        self.assertGreaterEqual(deleted["messageCount"], 1)
        self.assertTrue(all(not path.exists() for path in media_paths))

        with self.server.database.connect() as conn:
            self.assertEqual(0, conn.execute("SELECT COUNT(*) FROM cases WHERE id=?", (case_id,)).fetchone()[0])
            self.assertEqual(0, conn.execute("SELECT COUNT(*) FROM photos WHERE case_id=?", (case_id,)).fetchone()[0])
            self.assertEqual(0, conn.execute("SELECT COUNT(*) FROM messages WHERE case_id=?", (case_id,)).fetchone()[0])
            self.assertEqual(0, conn.execute("SELECT COUNT(*) FROM patients WHERE id=?", (patient_id,)).fetchone()[0])

    def test_admin_can_auto_generate_unique_usernames_from_display_name(self):
        admin = self.login("admin", "demo123")
        first = self.request("POST", "/admin/users", {
            "displayName": "Işık Şen", "role": "doctor", "password": "Temporary!123"
        }, token=admin, expected=201)["user"]
        second = self.request("POST", "/admin/users", {
            "displayName": "Işık Şen", "role": "doctor", "password": "Temporary!456"
        }, token=admin, expected=201)["user"]
        self.assertEqual("isik.sen", first["username"])
        self.assertEqual("isik.sen2", second["username"])

    def test_manager_can_read_everything_but_cannot_change_records(self):
        manager = self.login("manager", "demo123")
        all_cases = self.request("GET", "/cases", token=manager)["cases"]
        admin_cases = self.request("GET", "/admin/cases", token=manager)["cases"]
        users = self.request("GET", "/admin/users", token=manager)["users"]
        agencies = self.request("GET", "/admin/agencies", token=manager)["agencies"]
        self.assertEqual(len(admin_cases), len(all_cases))
        self.assertGreater(len(users), 0)
        self.assertGreater(len(agencies), 0)

        target = next(item for item in admin_cases if item["doctorID"] is None)
        assignment = self.request("PATCH", f"/admin/patients/{target['patientID']}", {
            "doctorID": "doctor-emre", "reason": "Manager must remain read-only"
        }, token=manager, expected=403)
        self.assertEqual("forbidden", assignment["error"]["code"])

        create_user = self.request("POST", "/admin/users", {
            "username": "manager-cannot-create", "displayName": "Blocked User",
            "role": "doctor", "password": "Temporary!123"
        }, token=manager, expected=403)
        self.assertEqual("forbidden", create_user["error"]["code"])
        rename_agency = self.request("PATCH", f"/admin/agencies/{agencies[0]['id']}", {
            "name": "Manager cannot rename"
        }, token=manager, expected=403)
        self.assertEqual("forbidden", rename_agency["error"]["code"])
        edit_user = self.request("PATCH", f"/admin/users/{users[0]['id']}", {
            "displayName": "Manager cannot edit"
        }, token=manager, expected=403)
        self.assertEqual("forbidden", edit_user["error"]["code"])


if __name__ == "__main__":
    unittest.main()
