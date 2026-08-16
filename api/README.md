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

## Tests

```bash
cd api
python3 -m unittest discover -s tests -v
```
