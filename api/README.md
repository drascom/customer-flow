# Customer Flow API

The API contains the versioned HTTP endpoints, authentication, SQLite database layer and uploaded-media storage used by Customer Flow clients. It can also serve the separate [`../admin-panel/`](../admin-panel/) interface.

## Requirements

- Python 3.9 or newer
- No third-party Python packages are required

## Simple local setup

```bash
cd api
export CF_ADMIN_PASSWORD='change-this-admin-password'
export CF_DOCTOR_PASSWORD='change-this-doctor-password'
export CF_AGENT_PASSWORD='change-this-agent-password'
python3 app.py --host 0.0.0.0 --port 8080
```

Open:

- Health check: `http://localhost:8080/api/v1/health`
- Admin panel: `http://localhost:8080/admin`

The first start creates the SQLite database in `data/customer-flow.sqlite3` and development users only when the database is empty. Accounts for real users should then be created from the admin panel. There is no public registration endpoint.

By default, the API loads the admin panel from the sibling `../admin-panel` folder. Set `CF_ADMIN_DIR` if you deploy that folder somewhere else on the same host.

## Agency integrations and idempotent writes

Agent case lists, patient matching, patient reuse, case details and photo access
are scoped to the agent's agency. An agent without an agency can access only
their own records. Supplying a patient ID from another agency is treated as a
missing patient rather than revealing that the record exists.

Integration clients should send an `Idempotency-Key` header when creating a
case, adding an agent update or uploading a case photo. Keys must contain 8-128
letters, numbers, `.`, `_`, `:` or `-`. Repeating the exact request with the
same key returns the current case without repeating the database mutation or
publishing another live-change event. Reusing a key with different request data
returns `409 idempotency_conflict`. Existing mobile clients remain compatible:
the header is optional.

The agency MCP connector and its deployment guide are in
[`../mcp-server/`](../mcp-server/).

Set `CF_PUBLIC_BASE_URL=https://customer-flow.example.com` to the HTTPS address
of your own deployment so admin connection details use the correct common
endpoint. Only an admin may call:

- `GET /api/v1/admin/agencies/{agencyID}/mcp` — endpoint and rotation status,
  never the token.
- `POST /api/v1/admin/agencies/{agencyID}/mcp/rotate` — generate/replace the
  agency token; plaintext is returned once and only its SHA-256 digest is stored.

Rotation immediately invalidates the old token and reuses the agency's managed
MCP service account for stable audit ownership.

The `cfmcp_` bearer token is not a general API session. It is accepted only for
the managed service account's identity, agency case list/detail/create, agent
updates and case photo uploads. All other authenticated routes return
`403 mcp_scope_forbidden`. MCP writes therefore pass through the same API event,
validation and idempotency paths as mobile/web writes.

## Notifications and Apple Push Notifications

Notifications are stored in the API database and appear in both the web and
iOS notification centres. Recipient scope is enforced by the API:

- admins and managers receive every case event;
- active members of the case's agency receive that agency's case events;
- every active doctor receives a new-case notification;
- after assignment, only the assigned doctor receives later case events;
- the user who performed the action is excluded from that action's recipients.

The iOS app registers its APNs device token after sign-in. Background and lock
screen delivery is enabled when the API service has an Apple provider key.

### Production APNs setup

This deployment uses Production APNs for TestFlight and App Store builds.

1. Open [Apple Developer → Certificates, Identifiers & Profiles → Keys](https://developer.apple.com/account/resources/authkeys/list)
   and select the organisation's Apple Developer team.
2. Add a key, give it a recognisable name such as `Customer Flow APNs`, and
   enable **Apple Push Notifications service (APNs)**.
3. Choose **Production**, then **Topic Specific**, and add the
   `com.customerflow.client` topic.
4. Review and register the key, then download the `.p8` file immediately.
   Apple permits this private key file to be downloaded only once.
5. Record the Key ID shown by Apple and the team's 10-character Team ID. The
   Team ID is also displayed beside the team name in the developer portal.

Keep the downloaded key outside the repository and restrict it to the API
service user. For the provided system-level service, one suitable layout is:

```bash
sudo install -d -o customer-flow -g customer-flow -m 700 /etc/customer-flow/apns
sudo install -o customer-flow -g customer-flow -m 600 \
  /path/to/AuthKey_KEYID.p8 /etc/customer-flow/apns/
```

Add these values to the protected `/etc/customer-flow/api.env` file:

```bash
CF_APNS_KEY_ID=APPLE_KEY_ID
CF_APNS_TEAM_ID=APPLE_TEAM_ID
CF_APNS_PRIVATE_KEY=/etc/customer-flow/apns/AuthKey_KEYID.p8
CF_APNS_TOPIC=com.example.customerflow
```

Reload and restart the API:

```bash
sudo systemctl daemon-reload
sudo systemctl restart customer-flow-api
sudo systemctl is-active customer-flow-api
```

The same values can be exported directly when the API is run without systemd:

```bash
export CF_APNS_KEY_ID='APPLE_KEY_ID'
export CF_APNS_TEAM_ID='APPLE_TEAM_ID'
export CF_APNS_PRIVATE_KEY='/secure/path/AuthKey_KEYID.p8'
export CF_APNS_TOPIC='com.customerflow.client'
```

Without these four values, notifications remain fully available in-app and on
the dashboard; only the external Apple push delivery worker stays disabled.
The provider key must remain outside the repository with read access limited to
the API service user. Delivery attempts use a durable outbox and invalid APNs
device tokens are removed automatically.

Install the app through TestFlight when testing this Production configuration.
An app launched directly from Xcode with a Debug configuration receives a
Sandbox device token and therefore does not receive pushes from this
Production-only key. Never commit `.p8` files; `*.p8` is excluded by the root
`.gitignore`. Keep a protected offline backup because Apple does not allow the
private key to be downloaded again.

## Password recovery by email

Set these variables before starting the server:

```bash
export CF_SMTP_HOST='smtp.example.com'
export CF_SMTP_PORT='465'
export CF_SMTP_USERNAME='smtp-user'
export CF_SMTP_PASSWORD='smtp-password'
export CF_SMTP_FROM='Customer Flow <no-reply@example.com>'
```

Implicit TLS is used by default. Set `CF_SMTP_SSL=0` to use STARTTLS. Firebase is not used.

## Production notes

- Put the service behind an HTTPS reverse proxy.
- Use strong initial passwords and protect all environment variables.
- Back up `data/` and `media/` securely.
- Never commit the SQLite database, uploaded patient media or SMTP credentials.
- The optional systemd unit in `deploy/` is an example and may need path changes for your server.

### Automatic deployment

The managed production and public demo installations can check `origin/main`
once per minute and restart their API service after a clean fast-forward update.
The deployment scripts refuse to overwrite tracked local changes, verify the
local health endpoint after restart, and roll the application checkout back if
the new revision does not become healthy. Database files, uploaded media and
environment files are untracked or stored outside the repository and are not
changed by deploys.

- Production user units and script: `deploy/production/`
- Public demo system units and script: `deploy/demo/`

The public demo deploy and hourly reset scripts share a maintenance lock so a
code update cannot race with a database reset.

## Tests

```bash
cd api
python3 -m unittest discover -s tests -v
```
