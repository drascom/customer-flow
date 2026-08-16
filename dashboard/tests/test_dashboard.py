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

    def test_dashboard_proxies_permanent_admin_case_deletion(self):
        headers = {"Authorization": self.authorization}
        with urlopen(Request(self.base + "/api/v1/admin/cases", headers=headers)) as response:
            target = json.load(response)["cases"][0]

        request = Request(
            self.base + f"/api/v1/admin/cases/{target['id']}",
            headers=headers,
            method="DELETE",
        )
        with urlopen(request) as response:
            deleted = json.load(response)["case"]
        self.assertTrue(deleted["deleted"])

        with urlopen(Request(self.base + "/api/v1/admin/cases", headers=headers)) as response:
            remaining = json.load(response)["cases"]
        self.assertNotIn(target["id"], {item["id"] for item in remaining})

    def test_dashboard_proxies_admin_only_mcp_connection_rotation(self):
        headers = {"Authorization": self.authorization, "Content-Type": "application/json"}
        with urlopen(Request(self.base + "/api/v1/admin/agencies", headers=headers)) as response:
            agency = json.load(response)["agencies"][0]
        with urlopen(Request(
            self.base + f"/api/v1/admin/agencies/{agency['id']}/mcp/rotate",
            data=b"{}", headers=headers, method="POST",
        )) as response:
            connection = json.load(response)["connection"]
        self.assertTrue(connection["accessToken"].startswith("cfmcp_"))
        with urlopen(Request(
            self.base + f"/api/v1/admin/agencies/{agency['id']}/mcp", headers=headers,
        )) as response:
            info = json.load(response)["connection"]
        self.assertTrue(info["configured"])
        self.assertNotIn("accessToken", info)


if __name__ == "__main__":
    unittest.main()
