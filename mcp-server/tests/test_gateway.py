import base64
import asyncio
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from customer_flow_mcp.config import ConfigurationError, Settings
from customer_flow_mcp.gateway import AgencyGateway, GatewayError
from customer_flow_mcp.api_client import CustomerFlowAPIClient
from customer_flow_mcp.server import AgencyTokenVerifier, build_server


def sample_case(reference="HT-240910", case_id="case-internal-1"):
    return {
        "id": case_id,
        "reference": reference,
        "patient": {
            "id": "PT-1110",
            "name": "Test Patient",
            "lastUpdated": "2026-08-16T10:00:00Z",
            "dateOfBirth": "1990-01-02",
            "statedAge": None,
            "age": 36,
            "gender": "male",
            "phone": "+44 7000 000000",
            "email": "patient@example.test",
            "address": "London",
            "occupation": "Engineer",
            "profileNote": "Contact in the afternoon",
            "assignedDoctorID": "doctor-internal",
        },
        "agentID": "agent-internal",
        "agentName": "Agency Integration",
        "agencyName": "Test Agency",
        "assignedDoctorID": "doctor-internal",
        "uploadedAt": "2026-08-16T09:00:00Z",
        "status": "waiting",
        "photoCount": 1,
        "photoIDs": ["photo-internal"],
        "agentNote": "Consultation note",
        "agentGrafts": "2400",
        "currency": "GBP",
        "agentPrice": "2200",
        "finalGrafts": None,
        "finalPrice": None,
        "finalizedAt": None,
        "messages": [{
            "id": "message-internal",
            "authorID": "doctor-internal",
            "author": "Doctor 1",
            "role": "doctor",
            "createdAt": "2026-08-16T10:00:00Z",
            "text": "Please add a donor photo.",
            "approximateGrafts": None,
            "recommendedPrice": None,
            "attachmentPhotoID": None,
        }],
    }


class FakeClient:
    def __init__(self, role="agent", agency_id="agency-1"):
        self.user = {
            "id": "agent-internal",
            "username": "integration.agent",
            "displayName": "Agency Integration",
            "role": role,
            "agencyID": agency_id,
        }
        self.cases = [sample_case()]
        self.created_payload = None
        self.update = None
        self.upload = None

    def me(self):
        return self.user

    def list_cases(self):
        return self.cases

    def get_case(self, case_id):
        return next(case for case in self.cases if case["id"] == case_id)

    def create_case(self, payload, idempotency_key):
        self.created_payload = (payload, idempotency_key)
        created = sample_case("HT-240911", "case-internal-2")
        created["patient"]["name"] = payload["patientName"]
        return created

    def add_agent_update(self, case_id, text, idempotency_key):
        self.update = (case_id, text, idempotency_key)
        return self.get_case(case_id)

    def upload_case_photo(self, case_id, body, media_type, idempotency_key):
        self.upload = (case_id, body, media_type, idempotency_key)
        return self.get_case(case_id)


def settings(**overrides):
    values = dict(
        database_path=Path("/tmp/customer-flow-test.sqlite3"),
        media_root=Path("/tmp/customer-flow-media"),
        public_base_url="https://flow.example",
    )
    values.update(overrides)
    return Settings(**values)


class GatewayTests(unittest.TestCase):
    def test_rejects_non_agent_or_unassigned_principal(self):
        with self.assertRaisesRegex(GatewayError, "active agent"):
            AgencyGateway(settings(), FakeClient(role="admin")).who_am_i()
        with self.assertRaisesRegex(GatewayError, "active agent"):
            AgencyGateway(settings(), FakeClient(agency_id=None)).who_am_i()

    def test_list_and_detail_remove_all_internal_identifiers(self):
        gateway = AgencyGateway(settings(), FakeClient())
        listing = gateway.list_cases()
        self.assertEqual("HT-240910", listing["cases"][0]["case_reference"])
        detail = gateway.get_case("ht-240910")
        encoded = repr(detail)
        for secret_id in (
            "case-internal", "PT-1110", "agent-internal", "doctor-internal",
            "photo-internal", "message-internal",
        ):
            self.assertNotIn(secret_id, encoded)
        self.assertEqual("Doctor 1", detail["messages"][0]["author"])
        self.assertEqual("confidential_patient_data", detail["data_classification"])

    def test_unknown_reference_never_calls_get_case(self):
        gateway = AgencyGateway(settings(), FakeClient())
        with self.assertRaisesRegex(GatewayError, "not found in this agency"):
            gateway.get_case("HT-999999")

    def test_updated_after_requires_timezone(self):
        gateway = AgencyGateway(settings(), FakeClient())
        with self.assertRaisesRegex(GatewayError, "include a timezone"):
            gateway.list_cases(updated_after="2026-08-16T09:00:00")
        result = gateway.list_cases(updated_after="2026-08-16T09:00:00Z")
        self.assertEqual(1, result["count"])

    def test_writes_are_disabled_by_default(self):
        gateway = AgencyGateway(settings(), FakeClient())
        with self.assertRaisesRegex(GatewayError, "Write tools are disabled"):
            gateway.add_case_message("HT-240910", "Hello", "message:12345678")

    def test_create_case_links_only_through_an_visible_previous_case(self):
        client = FakeClient()
        gateway = AgencyGateway(settings(enable_writes=True), client)
        result = gateway.create_case(
            "Second Consultation",
            "2500",
            "2300",
            "New consultation",
            "case:create:12345678",
            previous_case_reference="HT-240910",
        )
        payload, key = client.created_payload
        self.assertEqual("PT-1110", payload["existingPatientID"])
        self.assertEqual("case:create:12345678", key)
        self.assertEqual("HT-240911", result["case_reference"])
        self.assertNotIn("PT-1110", repr(result))

    def test_rejects_bad_idempotency_key_before_write(self):
        gateway = AgencyGateway(settings(enable_writes=True), FakeClient())
        with self.assertRaisesRegex(GatewayError, "idempotency_key"):
            gateway.add_case_message("HT-240910", "Hello", "short")

    def test_photo_upload_validates_signature_and_size(self):
        client = FakeClient()
        gateway = AgencyGateway(
            settings(enable_writes=True, enable_photo_uploads=True, max_photo_bytes=32),
            client,
        )
        jpeg = b"\xff\xd8\xff" + b"safe-image"
        gateway.upload_case_photo(
            "HT-240910", "image/jpeg", base64.b64encode(jpeg).decode(), "photo:12345678"
        )
        self.assertEqual(jpeg, client.upload[1])
        with self.assertRaisesRegex(GatewayError, "do not match"):
            gateway.upload_case_photo(
                "HT-240910", "image/png", base64.b64encode(jpeg).decode(), "photo:87654321"
            )


class SettingsTests(unittest.TestCase):
    def test_requires_https_public_url(self):
        with patch.dict(os.environ, {
            "CF_PUBLIC_BASE_URL": "http://flow.example",
        }, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "must use HTTPS"):
                Settings.from_env()

    def test_loopback_http_requires_explicit_development_flag(self):
        with patch.dict(os.environ, {
            "CF_PUBLIC_BASE_URL": "http://127.0.0.1:8080",
            "CF_MCP_ALLOW_INSECURE_HTTP": "true",
        }, clear=True):
            loaded = Settings.from_env()
        self.assertEqual("http://127.0.0.1:8080/mcp", loaded.public_mcp_url)

    def test_public_bind_requires_acknowledgement(self):
        with patch.dict(os.environ, {
            "CF_PUBLIC_BASE_URL": "https://flow.example",
            "CF_MCP_HOST": "0.0.0.0",
        }, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "Bind the MCP service"):
                Settings.from_env()

    def test_internal_api_rejects_cleartext_non_loopback_url(self):
        with patch.dict(os.environ, {
            "CF_PUBLIC_BASE_URL": "https://flow.example",
            "CF_API_BASE_URL": "http://api.example/api/v1",
        }, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "must use HTTPS"):
                Settings.from_env()


class SharedAgencyTokenTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        api_path = Path(__file__).resolve().parents[2] / "api"
        sys.path.insert(0, str(api_path))
        from app import Database, create_server

        root = Path(self.temp.name)
        self.database = Database(root / "test.sqlite3", root / "media")
        self.database.initialize(seed=True)
        with self.database.connect() as conn:
            self.admin = conn.execute("SELECT * FROM users WHERE role='admin' LIMIT 1").fetchone()
            agencies = conn.execute("SELECT * FROM agencies ORDER BY id").fetchall()
        self.assertGreaterEqual(len(agencies), 2)
        self.agency_one, self.agency_two = agencies[:2]
        self.first = self.database.admin_rotate_mcp_token(self.agency_one["id"], self.admin)
        self.second = self.database.admin_rotate_mcp_token(self.agency_two["id"], self.admin)
        self.api_server = create_server(
            "127.0.0.1", 0, root / "test.sqlite3", root / "media", seed=False
        )
        self.api_thread = threading.Thread(target=self.api_server.serve_forever, daemon=True)
        self.api_thread.start()
        self.settings = settings(
            database_path=root / "test.sqlite3",
            media_root=root / "media",
            api_base_url=f"http://127.0.0.1:{self.api_server.server_port}/api/v1",
        )

    def tearDown(self):
        self.api_server.shutdown()
        self.api_server.server_close()
        self.api_thread.join(timeout=2)
        self.temp.cleanup()

    def _gateway(self, connection, **setting_overrides):
        gateway_settings = self.settings
        if setting_overrides:
            gateway_settings = settings(
                database_path=self.settings.database_path,
                media_root=self.settings.media_root,
                api_base_url=self.settings.api_base_url,
                **setting_overrides,
            )
        return AgencyGateway(
            gateway_settings,
            CustomerFlowAPIClient(gateway_settings, connection["accessToken"]),
        )

    def test_official_verifier_resolves_exactly_one_agency(self):
        verifier = AgencyTokenVerifier(self.database, self.settings.public_mcp_url)
        access = asyncio.run(verifier.verify_token(self.first["accessToken"]))
        self.assertIsNotNone(access)
        self.assertEqual(self.agency_one["id"], access.claims["agency_id"])
        self.assertEqual(["customer-flow:agency"], access.scopes)
        self.assertIsNone(asyncio.run(verifier.verify_token("cfmcp_" + "x" * 64)))

    def test_cross_agency_case_reference_is_denied(self):
        first_gateway = self._gateway(self.first)
        second_cases = self._gateway(self.second).list_cases()["cases"]
        self.assertTrue(second_cases)
        with self.assertRaisesRegex(GatewayError, "not found in this agency"):
            first_gateway.get_case(second_cases[0]["case_reference"])

    def test_gateway_write_uses_api_and_publishes_realtime_event(self):
        gateway = self._gateway(self.first, enable_writes=True)
        before = self.api_server.changes.wait(-1, timeout=0)
        created = gateway.create_case(
            "MCP Realtime Patient",
            "2400",
            "2200",
            "Created through the HTTP-backed MCP gateway",
            "mcp:create:realtime123",
        )
        after = self.api_server.changes.wait(before["revision"], timeout=0.1)
        self.assertTrue(after["changed"])
        self.assertEqual("case.created", after["event"]["kind"])
        self.assertIn(
            created["case_reference"],
            [item["case_reference"] for item in gateway.list_cases()["cases"]],
        )

    def test_server_uses_shared_streamable_http_auth(self):
        server = build_server(self.settings, self.database)
        from starlette.testclient import TestClient

        request = {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "security-test", "version": "1"},
            },
        }
        headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "MCP-Protocol-Version": "2025-06-18",
        }
        with TestClient(server.streamable_http_app(), base_url="http://127.0.0.1:8091") as client:
            self.assertEqual(401, client.post("/mcp", json=request, headers=headers).status_code)
            authorized = client.post(
                "/mcp", json=request,
                headers={**headers, "Authorization": f"Bearer {self.first['accessToken']}"},
            )
            self.assertEqual(200, authorized.status_code, authorized.text)
            tool_call = client.post(
                "/mcp",
                json={
                    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": {"name": "who_am_i", "arguments": {}},
                },
                headers={**headers, "Authorization": f"Bearer {self.first['accessToken']}"},
            )
            self.assertEqual(200, tool_call.status_code, tool_call.text)
            self.assertIn(self.agency_one["id"], tool_call.text)
            replacement = self.database.admin_rotate_mcp_token(self.agency_one["id"], self.admin)
            rejected_old = client.post(
                "/mcp", json=request,
                headers={**headers, "Authorization": f"Bearer {self.first['accessToken']}"},
            )
            self.assertEqual(401, rejected_old.status_code)
            accepted_new = client.post(
                "/mcp", json=request,
                headers={**headers, "Authorization": f"Bearer {replacement['accessToken']}"},
            )
            self.assertEqual(200, accepted_new.status_code, accepted_new.text)


if __name__ == "__main__":
    unittest.main()
