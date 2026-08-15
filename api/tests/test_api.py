import json
import os
import tempfile
import threading
import unittest
import uuid
from http.client import HTTPConnection
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

    def raw_request(self, method, path, body=None, content_type=None, token=None, expected=200):
        headers = {}
        if content_type:
            headers["Content-Type"] = content_type
        if token:
            headers["Authorization"] = f"Bearer {token}"
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
        result = self.request("POST", "/auth/login", {"username": "doctor1", "password": "demo123"})
        self.assertEqual("doctor", result["user"]["role"])

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
        agent = self.login("user1", "demo123")
        doctor_cases = self.request("GET", "/cases", token=doctor)["cases"]
        agent_cases = self.request("GET", "/cases", token=agent)["cases"]
        self.assertGreater(len(doctor_cases), len(agent_cases))
        matches = self.request("GET", f"/patients/matches?name={quote('Çolak Ayhan')}", token=agent)["matches"]
        self.assertEqual("Ayhan Çolak", matches[0]["name"])
        self.assertTrue(matches[0]["createdByAnotherAgent"])

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
        closed = self.request("POST", f"/cases/{created['id']}/close", {}, token=agent)["case"]
        self.assertEqual("closed", closed["status"])

    def test_agent_uploads_and_authorized_users_fetch_real_photo(self):
        doctor = self.login("doctor1", "demo123")
        agent = self.login("user1", "demo123")
        created = self.request("POST", "/cases", {
            "patientName": "Photo Test Patient", "grafts": "2200", "currency": "GBP",
            "price": "2100", "note": "Real photo upload test", "photoCount": 2,
        }, token=agent, expected=201)["case"]
        self.assertEqual(2, created["photoCount"])
        self.assertEqual(2, len(created["photoIDs"]))

        jpeg = b"\xff\xd8customer-flow-test-photo\xff\xd9"
        uploaded_body, _ = self.raw_request(
            "POST", f"/cases/{created['id']}/photos", body=jpeg,
            content_type="image/jpeg", token=agent, expected=201,
        )
        uploaded = json.loads(uploaded_body)["case"]
        self.assertEqual(2, uploaded["photoCount"])
        self.assertEqual(created["photoIDs"], uploaded["photoIDs"])

        photo_body, photo_headers = self.raw_request(
            "GET", f"/photos/{created['photoIDs'][0]}", token=doctor,
        )
        self.assertEqual(jpeg, photo_body)
        self.assertEqual("image/jpeg", photo_headers.get_content_type())
        self.raw_request("GET", f"/photos/{created['photoIDs'][0]}", expected=401)

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
