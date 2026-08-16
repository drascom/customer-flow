# Customer Flow agency MCP gateway

This service lets an agency connect an MCP-capable LLM or automation host to
Customer Flow without exposing admin functions or another agency's records.
It reuses the Customer Flow HTTP API as the authorization boundary rather than
reading the SQLite database directly.

## Security model

One running gateway instance is bound to **one dedicated Customer Flow agent
account**. On every tool call the gateway checks `/auth/me` and refuses to work
unless the account is active, has the `agent` role and belongs to an agency.
Customer Flow then applies its existing agency scope and owner-only write rules.

Use a different service account and gateway instance for every agency. Do not
configure an admin, manager, doctor, or personal employee account. The MCP
output removes internal case, patient, user, doctor, photo and message IDs.
Doctor names and replies remain visible only where they are part of an agency's
own case conversation.

The gateway is not a public authentication server. For a hosted deployment it
binds to loopback by default and must sit behind an MCP-compatible authenticated
reverse proxy or access gateway (OAuth 2.1 is preferred; mTLS is also suitable).
Never publish a per-agency endpoint without that edge authentication. `stdio`
is the safer default when the agency controls the MCP host.

All case results are classified as confidential patient data. The connected LLM
provider and its retention policy must be approved before enabling this service.

## Exposed surface

| Name | Default | Purpose |
| --- | --- | --- |
| `customer-flow://policy` | on | Connector scope and handling rules |
| `customer-flow://me` | on | Non-secret configured agency identity |
| `who_am_i` | on | Confirm the agency account and enabled capabilities |
| `list_cases` | on | Agency-only case summaries, filtered and capped at 100 |
| `get_case` | on | One agency case by its `HT-...` reference |
| `create_case` | off | Create a case with an API-transaction idempotency key |
| `add_case_message` | off | Add an owner-agent message with an idempotency key |
| `upload_case_photo` | off | Validate and upload base64 JPEG/PNG/HEIC data |

Writes appear only when `CF_MCP_ENABLE_WRITES=true`. Photo upload additionally
requires `CF_MCP_ENABLE_PHOTO_UPLOADS=true`. The server deliberately does not
offer patient matching, delete, close/confirm, doctor assignment, user/agency
management, admin, or doctor tools.

Every write requires an `idempotency_key` (8-128 safe ASCII characters). Reuse
the same key only when retrying the exact same operation and payload. Customer
Flow stores the request fingerprint and resulting entity reference in the same database
transaction as the write, so network retries do not create duplicate cases,
messages, or photos.

Photo payloads are disabled by default because base64 increases both request
size and LLM exposure. When enabled, the gateway verifies MIME type, file
signature, base64 validity and decoded size. A future signed-upload flow is
preferable for large production media transfers.

## Install and test

Python 3.11 or newer is required.

```bash
cd mcp-server
python3 -m venv .venv
.venv/bin/pip install -r requirements.lock
.venv/bin/pip install --no-deps .
.venv/bin/python -m unittest discover -s tests -v
```

Copy `.env.example` to a secret environment file outside the repository. Do not
commit credentials. Create the dedicated agent account from the Customer Flow
admin UI and assign it to the correct agency before starting the gateway.

For local development over plain HTTP, only a loopback API is accepted:

```bash
export CF_MCP_API_BASE_URL=http://127.0.0.1:8080
export CF_MCP_ALLOW_INSECURE_HTTP=true
```

## Run with an MCP host (stdio)

Configure the MCP host to launch:

```bash
/absolute/path/customer-flow/mcp-server/.venv/bin/customer-flow-mcp
```

Pass the `CF_MCP_*` values through the host's secret environment configuration.
Do not place passwords or session tokens in the MCP prompt or tool arguments.

## Run as Streamable HTTP

Set:

```bash
CF_MCP_TRANSPORT=streamable-http
CF_MCP_HOST=127.0.0.1
CF_MCP_PORT=8091
CF_MCP_PATH=/mcp
```

Clients then connect through the authenticated public proxy URL, for example
`https://flow.drascom.uk/agency-mcp/mcp`. The proxy must preserve MCP request and
response headers and enforce an agency-specific identity before forwarding.
Keep upstream routing one-to-one: an agency endpoint must never route to another
agency's gateway instance. If photo upload is enabled, align the proxy body
limit with `CF_MCP_MAX_PHOTO_BYTES` plus base64 overhead.

The supplied user service is a template. Install dependencies in
`mcp-server/.venv`, put secrets in `/home/dr/.config/customer-flow/mcp.env` with
mode `0600`, then install/enable the service for the deployment user. Run one
renamed service unit per agency.

## Credential rotation and failure behaviour

- Username/password mode obtains and refreshes the API's seven-day session
  without returning the session token to the MCP client.
- Token-only mode stops working when the token expires; rotate it out of band.
- Deactivating or changing the service account immediately causes API calls to
  fail. The gateway never falls back to a broader role.
- API errors returned to MCP omit backend `details`, preventing identifiers from
  being surfaced accidentally.

## Production follow-ups

Before offering a single shared multi-tenant MCP URL, implement MCP/OAuth token
verification with per-request agency claims and map those claims to short-lived
Customer Flow API credentials. The current per-agency instance model is
intentional: it is easier to audit and cannot silently switch tenants inside a
long-lived MCP session.
