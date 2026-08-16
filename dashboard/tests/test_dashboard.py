import importlib.util
import base64
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
        cls.dashboard = dashboard_app.create_server(
            "127.0.0.1",
            0,
            f"http://127.0.0.1:{cls.api.server_port}",
            ROOT / "admin-panel",
            "admin",
            "demo123",
            "73918426",
        )
        cls.dashboard_thread = threading.Thread(target=cls.dashboard.serve_forever, daemon=True)
        cls.dashboard_thread.start()
        cls.base = f"http://127.0.0.1:{cls.dashboard.server_port}"
        cls.authorization = "Basic " + base64.b64encode(b"admin:73918426").decode()

    @classmethod
    def tearDownClass(cls):
        cls.dashboard.shutdown()
        cls.dashboard.server_close()
        cls.api.shutdown()
        cls.api.server_close()
        cls.temp.cleanup()

    def test_dashboard_is_direct_and_proxies_admin_reads(self):
        with self.assertRaises(HTTPError) as unauthorized:
            urlopen(self.base + "/")
        self.assertEqual(401, unauthorized.exception.code)

        with urlopen(Request(self.base + "/", headers={"Authorization": self.authorization})) as response:
            html = response.read()
        self.assertIn(b'data-direct-admin="true"', html)
        self.assertIn(b'<main id="loginView" hidden', html)
        self.assertIn(b'<div id="appView" class="app-shell">', html)

        with urlopen(Request(self.base + "/api/v1/admin/cases", headers={"Authorization": self.authorization})) as response:
            payload = json.load(response)
        self.assertGreater(len(payload["cases"]), 0)

    def test_dashboard_does_not_expose_auth_routes_or_cross_origin_mutations(self):
        with self.assertRaises(HTTPError) as missing:
            urlopen(Request(self.base + "/api/v1/auth/me", headers={"Authorization": self.authorization}))
        self.assertEqual(404, missing.exception.code)

        request = Request(
            self.base + "/api/v1/admin/agencies",
            data=json.dumps({"name": "Blocked"}).encode(),
            headers={"Content-Type": "application/json", "Origin": "https://example.test", "Authorization": self.authorization},
            method="POST",
        )
        with self.assertRaises(HTTPError) as forbidden:
            urlopen(request)
        self.assertEqual(403, forbidden.exception.code)


if __name__ == "__main__":
    unittest.main()
