import base64
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from customer_flow_mcp.config import ConfigurationError, Settings
from customer_flow_mcp.gateway import AgencyGateway, GatewayError


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
        api_base_url="https://flow.example/api/v1",
        api_token="secret-token",
        api_username=None,
        api_password=None,
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
    def test_requires_credentials_and_https(self):
        with patch.dict(os.environ, {"CF_MCP_API_BASE_URL": "https://flow.example"}, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "CF_MCP_API_TOKEN"):
                Settings.from_env()
        with patch.dict(os.environ, {
            "CF_MCP_API_BASE_URL": "http://flow.example",
            "CF_MCP_API_TOKEN": "secret",
        }, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "must use HTTPS"):
                Settings.from_env()

    def test_loopback_http_requires_explicit_development_flag(self):
        with patch.dict(os.environ, {
            "CF_MCP_API_BASE_URL": "http://127.0.0.1:8080",
            "CF_MCP_ALLOW_INSECURE_HTTP": "true",
            "CF_MCP_API_TOKEN": "secret",
        }, clear=True):
            loaded = Settings.from_env()
        self.assertEqual("http://127.0.0.1:8080/api/v1", loaded.api_base_url)

    def test_public_bind_requires_acknowledgement(self):
        with patch.dict(os.environ, {
            "CF_MCP_API_BASE_URL": "https://flow.example",
            "CF_MCP_API_TOKEN": "secret",
            "CF_MCP_TRANSPORT": "streamable-http",
            "CF_MCP_HOST": "0.0.0.0",
        }, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "Public MCP binding"):
                Settings.from_env()


if __name__ == "__main__":
    unittest.main()
