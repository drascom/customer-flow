# Customer Flow agency MCP server

This is the shared Streamable HTTP MCP endpoint for agency LLM and automation
systems. Every client connects to its deployment's common endpoint, such as
`https://customer-flow.example.com/mcp`, and sends the
single bearer token generated for its agency by a Customer Flow administrator.

## Security boundary

- The API stores only a SHA-256 digest of each high-entropy token. Plaintext is
  returned only by generate/rotate and cannot be recovered later.
- There is exactly one active token per agency. Rotation replaces its digest in
  one transaction, so the previous token stops authenticating immediately.
- The official MCP SDK `TokenVerifier` resolves each request to one agency and
  one managed agent service account. Every tool then calls the normal HTTP API
  with that request's MCP bearer token, preserving API validation, audit rules
  and realtime `ChangeBroker` notifications.
- The service account is created automatically and cannot be edited, disabled,
  or deleted through normal user-management endpoints. It owns MCP-created cases
  for audit. Its tools may update, message, or add photos to another case only
  when that case belongs to the same agency resolved from the MCP token.
- MCP never accepts an employee password or session token. Agency employees
  cannot generate or rotate MCP tokens; these API operations are admin-only.
- Internal IDs are removed from tool results. Admin, doctor assignment, delete,
  close/confirm, user management and cross-agency discovery tools are absent.

The verifier reads the token digest from the API database, but tool data access
goes only through the API's narrow MCP bearer scope. That scope allows
`GET /auth/me`, case list/detail/create, case metadata updates, agent messages
and case photo uploads within the resolved agency;
events, profiles, password operations, admin routes, deletes, doctor messages,
case closing and every other authenticated route are rejected. Run MCP on the
API host and set `CF_API_BASE_URL=http://127.0.0.1:8080/api/v1`. Tokens are bearer
secrets: the agency and any LLM provider that receives one can access that
agency's confidential patient data until an admin rotates it.

## Tools and resources

| Name | Default | Purpose |
| --- | --- | --- |
| `customer-flow://policy` | on | Scope and confidential-data handling rules |
| `customer-flow://me` | on | Authenticated agency identity, never the token |
| `who_am_i` | on | Confirm tenant and enabled capabilities |
| `list_cases` | on | Agency-only summaries, capped at 100 |
| `get_case` | on | One agency case by `HT-...` reference |
| `create_case` | off | Idempotent creation of a genuinely new consultation |
| `update_case` | off | Idempotent partial metadata update by exact `HT-...` reference |
| `add_case_message` | off | Idempotent message on an agency case |
| `upload_case_photo` | off | Validated base64 JPEG/PNG/HEIC upload |

Writes require `CF_MCP_ENABLE_WRITES=true`. Photos additionally require
`CF_MCP_ENABLE_PHOTO_UPLOADS=true`. Every write requires an 8-128 character
idempotency key; reusing a key with a different payload is rejected.

`create_case` records the patient and consultation metadata first. Its required
`patient_need` argument maps to the need shown on the case, while `address`,
`city`, and `region` remain separate patient fields. A new case then requires at
least one call to `upload_case_photo`. Tool results expose
`minimum_photo_count`, `photo_requirement_met`, and
`remaining_required_photos`; an automation must not consider the submission
complete until `photo_requirement_met` is true. This matches the current iOS
minimum of one photo.

Before creating a patient, integrations should call `list_cases` with the name
as `search`. `create_case` is only for a genuinely new consultation. Its result
contains a stable `case_reference` such as `HT-240910`; the connected system
must store that value as its Customer Flow record ID. Later corrections use
`update_case` with that exact reference and only the supplied fields are
changed. Reusing the same idempotency key safely retries the same update;
reusing it with different values is rejected. If the same patient starts a
genuinely new consultation, pass the earlier case as `previous_case_reference`.
Use `duplicate_confirmed_different` only after verifying that a same-name match
is a different person.

Case reads expose `workflow_state` using the product language:
`waiting_for_doctor`, `waiting_for_agent`, `confirmed`, or `closed`. A confirmed
case includes `appointment_at`; a closed conversation includes `closed_at` and
can reopen when either side sends a new message. `workflow_state` can also be
used as an optional `list_cases` filter. Confirmation, conversation closing,
and reopening remain outside the MCP write scope.

## Install and test

```bash
cd mcp-server
python3 -m venv .venv
.venv/bin/pip install -r requirements.lock
.venv/bin/pip install --no-deps .
.venv/bin/python -m unittest discover -s tests -v
```

Copy `.env.example` to `/etc/customer-flow/mcp.env`, keep it mode
`0600`, point the database/module paths at the deployed API, and keep
`CF_API_BASE_URL` on loopback. No agency token belongs in the service
environment.

Start with `customer-flow-mcp.service`. Configure the public proxy so only
`/mcp` forwards to `http://127.0.0.1:8091/mcp`, preserving `Authorization`,
`Accept`, `Content-Type`, `MCP-Protocol-Version`, and session-related headers.
Do not expose port 8091 directly.

An admin opens an agency in the iOS or web admin UI, presses **Generate access
token**, and copies the endpoint plus token once. **Rotate access token** is the
recovery path for disclosure or planned credential changes.

## Client configuration

Use the common URL and an authorization header:

```json
{
  "url": "https://customer-flow.example.com/mcp",
  "headers": { "Authorization": "Bearer cfmcp_REPLACE_WITH_ONE_TIME_TOKEN" }
}
```

Never put the token in prompts, tool arguments, source control, analytics, or
URLs. Approve the connected LLM provider's data-retention terms before exposing
patient records.

## Current trade-offs

- SHA-256 is appropriate because tokens contain 384 bits of random material,
  but a future deployment may add a server-side HMAC pepper for defense in depth.
- MCP verifies token hashes against the shared SQLite database, while clinical
  reads and writes pass through the HTTP API. SQLite/WAL is suitable for the
  current staging load; higher concurrency should move credentials and clinical
  data to a transactional server database.
- Write tools accept only exact case references visible inside the agency
  resolved from the bearer token. Cross-agency references remain undiscoverable
  and are rejected by both the gateway and API authorization boundary.
