import importlib.util
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "api"))
import app as api_app

spec = importlib.util.spec_from_file_location("dashboard_app", ROOT / "dashboard" / "app.py")
dashboard_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dashboard_app)


class DashboardTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        temp_root = Path(cls.temp.name)
        cls.api = api_app.create_server("127.0.0.1", 0, temp_root / "test.sqlite3", temp_root / "media", seed=True)
        cls.api_thread = threading.Thread(target=cls.api.serve_forever, daemon=True)
        cls.api_thread.start()
        cls.dashboard = dashboard_app.create_server("127.0.0.1", 0, f"http://127.0.0.1:{cls.api.server_port}", ROOT / "admin-panel")
        cls.dashboard_thread = threading.Thread(target=cls.dashboard.serve_forever, daemon=True)
        cls.dashboard_thread.start()
        cls.base = f"http://127.0.0.1:{cls.dashboard.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.dashboard.shutdown(); cls.dashboard.server_close(); cls.api.shutdown(); cls.api.server_close(); cls.temp.cleanup()

    def request(self, method, path, body=None, token=None, expected=200, content_type="application/json"):
        headers = {"Accept": "application/json"}
        if token: headers["Authorization"] = f"Bearer {token}"
        if body is not None: headers["Content-Type"] = content_type
        data = json.dumps(body).encode() if body is not None and content_type == "application/json" else body
        request = Request(self.base + path, data=data, headers=headers, method=method)
        try:
            response = urlopen(request)
        except HTTPError as error:
            response = error
        payload = response.read()
        self.assertEqual(expected, response.status, payload)
        return json.loads(payload) if response.headers.get_content_type() == "application/json" else payload

    def login(self, username):
        return self.request("POST", "/api/v1/auth/login", {"username": username, "password": "demo123"})["token"]

    def test_dashboard_serves_real_login_and_forwards_every_role(self):
        html = self.request("GET", "/")
        self.assertIn(b'id="loginForm"', html)
        self.assertNotIn(b"data-direct-admin", html)
        for username in ("admin", "manager", "user1", "doctor1"):
            token = self.login(username)
            me = self.request("GET", "/api/v1/auth/me", token=token)
            self.assertEqual(username, me["user"]["username"])

    def test_role_authorization_is_enforced_by_api(self):
        agent = self.login("user1")
        self.request("GET", "/api/v1/cases", token=agent)
        self.request("GET", "/api/v1/admin/users", token=agent, expected=403)

    def test_case_creation_and_photo_upload_forward_binary_and_headers(self):
        agent = self.login("user1")
        case = self.request("POST", "/api/v1/cases", {"patientName": "Web Patient", "grafts": "2300", "currency": "GBP", "price": "2200", "note": "Web flow", "photoCount": 1}, token=agent, expected=201)["case"]
        jpeg = b"\xff\xd8dashboard-photo\xff\xd9"
        uploaded = self.request("POST", f"/api/v1/cases/{case['id']}/photos", jpeg, agent, 201, "image/jpeg")["case"]
        photo = self.request("GET", f"/api/v1/photos/{uploaded['photoIDs'][0]}", token=agent)
        self.assertEqual(jpeg, photo)

    def test_cross_origin_mutation_is_rejected(self):
        request = Request(self.base + "/api/v1/auth/login", data=b"{}", headers={"Content-Type": "application/json", "Origin": "https://example.test"}, method="POST")
        with self.assertRaises(HTTPError) as forbidden: urlopen(request)
        self.assertEqual(403, forbidden.exception.code)


if __name__ == "__main__":
    unittest.main()
