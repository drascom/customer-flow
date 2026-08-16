# Customer Flow dashboard

This service exposes the existing management interface on port 80 without an API login screen. It creates the API admin session on the server and proxies only the management routes used by the dashboard, so the API password and bearer token are never sent to the browser. A separate browser PIN gate protects the port; use `admin` as the browser prompt username and the configured PIN as its password.

It is intended for the private staging network. Keep the PIN separate from the API admin password.

Run locally on a high port:

```sh
CF_DASHBOARD_ADMIN_PASSWORD=demo123 CF_DASHBOARD_PIN=change-me python3 dashboard/app.py --port 18080
```

The systemd unit reads optional overrides from `/home/dr/customer-flow/dashboard/dashboard.env`. Without overrides, it uses the staging seed account `admin / demo123`.
