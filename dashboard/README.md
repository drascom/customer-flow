# Customer Flow dashboard

This service exposes the existing management interface on port 80 without a browser login screen. It creates the API admin session on the server and proxies only the management routes used by the dashboard, so the API password and bearer token are never sent to the browser.

It is intended for the private staging network. Add the planned PIN/access layer before making port 80 public.

Run locally on a high port:

```sh
CF_DASHBOARD_ADMIN_PASSWORD=demo123 python3 dashboard/app.py --port 18080
```

The systemd unit reads optional overrides from `/home/dr/customer-flow/dashboard/dashboard.env`. Without overrides, it uses the staging seed account `admin / demo123`.
