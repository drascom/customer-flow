# Semble Connector — Detailed Implementation Plan

**Status:** Planning only — no application changes are authorised by this document.
**Last reviewed:** 2 October 2026
**Systems:** Customer Flow and Semble

## 1. Purpose

Build an optional, server-side connector between Customer Flow and Semble.

Customer Flow will remain the consultation and referral-workflow product: agency intake, case photos, doctor assessment, annotation, agent–doctor discussion, and consultation status stay in Customer Flow. Semble will remain the clinical practice-management system: patient records, appointments, procedures, documents, payments, and the operational patient journey.

The connector transfers an approved consultation into Semble and reflects selected Semble operational updates back to Customer Flow. It is a module, not a core Customer Flow function.

## 2. Non-negotiable design principles

1. **Optional per practice.** A clinic can use Customer Flow without Semble. An admin must be able to enable, pause, reconnect, or disable the connector without changing ordinary case workflow.
2. **Server-side only.** Semble tokens, webhook secrets, patient identifiers, and document upload URLs must never be placed in the iOS, Mac, or browser clients.
3. **No workflow dependency.** A Semble failure must never stop a case from being submitted, reviewed, answered, confirmed, or closed in Customer Flow.
4. **Clear ownership.** One system owns a field; the other may display a copy. The connector must not silently overwrite clinical or consultation data.
5. **Human review for identity uncertainty.** The connector may suggest a patient match but must not automatically merge ambiguous patient records.
6. **Auditable and recoverable.** Every handover, incoming event, retry, mapping decision, and manual intervention must be recorded.
7. **Least privilege.** The Semble API credential must receive only the permissions required by the enabled features.

## 3. Scope

### In scope

- Connection administration and health status.
- Semble patient search, matching, linking, and patient creation.
- Export of a selected Customer Flow consultation summary.
- Export of approved case photos as Semble patient documents.
- Saving Customer Flow and Semble identity mappings.
- Receiving and verifying Semble webhooks.
- Reflecting selected booking and journey status in Customer Flow.
- Retry, reconciliation, audit, and manual recovery tools.

### Explicitly out of scope for the first connector

- Replacing Customer Flow conversations with Semble messaging.
- Syncing doctor annotations as editable Semble data.
- Creating clinical reports, prescriptions, consent forms, invoices, or payments automatically.
- Making Customer Flow a source of truth for Semble calendars.
- Full historic patient/data migration.
- Automatic duplicate-patient merges.
- Native-client direct access to Semble.
- Multi-currency payment handling.

## 4. System-of-record policy

| Information | Owner | Connector behaviour |
| --- | --- | --- |
| Customer Flow case reference, workflow status, conversations, annotations | Customer Flow | Never replaced by Semble |
| Initial referral and agency context | Customer Flow | Export a readable snapshot to Semble when configured |
| Doctor assessment, approximate grafts, recommended price | Customer Flow | Export a summary only; retain structured values in Customer Flow |
| Patient core clinical record | Semble after link/creation | Customer Flow preserves its original intake snapshot and stores Semble patient ID |
| Appointment, procedure, booking, payment status | Semble | Customer Flow stores a display/status projection only |
| Consultation photos | Customer Flow | Copy selected photos to Semble documents; do not delete the originals |
| Semble document IDs and upload timestamps | Connector mapping store | Used to prevent duplicate uploads |

### Conflict rules

- Customer Flow does not update a linked Semble patient automatically after the initial handover in phase 1.
- Semble booking status may update the Customer Flow **Semble operational status** only; it may not close or reopen a Customer Flow consultation.
- If a Semble patient is deleted or becomes unavailable, mark the link as **Needs review** in Customer Flow. Do not remove Customer Flow clinical or consultation data.
- Any later two-way demographic sync requires a separately approved field-level ownership policy.

## 5. User experience and permissions

### Admin only

The following functionality belongs to the Customer Flow admin role:

- Enable, pause, reconnect, and disable the Semble connector.
- Select sandbox or production environment.
- Enter/rotate the Semble API credential through a secure server-side configuration flow.
- Configure handover trigger, photo rules, document naming, and selected webhook events.
- Resolve patient-match suggestions and conflicts.
- Trigger a manual handover or retry a failed sync.
- View connector audit logs, health, queue depth, and failures.

### Agent and doctor experience

- No Semble credentials or connection controls.
- Case details may show a small, read-only integration status: **Not sent**, **Linked**, **Syncing**, **Needs review**, or **Error**.
- When linked, show a Semble patient reference and selected operational booking state.
- Agents and doctors do not receive Semble administrative data, payment data, or broad patient-directory access through Customer Flow.

## 6. Connector configuration

Each practice must have at most one active Semble configuration per Customer Flow tenant.

| Setting | Example | Notes |
| --- | --- | --- |
| Connection state | Disabled / Active / Paused / Needs attention | Disabling stops new work but keeps mappings and audit history |
| Environment | Sandbox / Production | Credentials are environment-specific |
| API credential | Encrypted secret | Stored server-side only |
| Default handover trigger | Manual / Confirmed / Booked | Start with Manual in the pilot |
| Photo export rule | None / Selected / All approved consultation photos | Do not export drafts or deleted photos |
| Semble document naming prefix | `CF-{caseReference}` | Makes documents recognisable in Semble |
| Selected Semble event types | booking, patient, pathway, document | Minimal set first |
| Replay protection window | 5 minutes | Reject stale webhook signatures unless manually replayed through controlled recovery |
| Technical-contact alert recipient | Practice technical contact | Required for paused webhook subscriptions |

The production GraphQL endpoint is `https://open.semble.io/graphql`; Semble also provides a sandbox endpoint. Semble documents that settings-generated API tokens are suitable for server-side integrations and can be permission-scoped. [Semble authentication](https://docs.semble.io/docs/authentication/)

## 7. Internal data model

The connector requires its own isolated data tables/collections. Names below are conceptual, not an instruction to use a particular database technology.

### 7.1 `semble_connections`

| Field | Purpose |
| --- | --- |
| `id` | Internal connection identifier |
| `tenant_id` | Customer Flow practice/tenant |
| `environment` | Sandbox or production |
| `state` | Disabled, active, paused, needs_attention |
| `encrypted_api_token` | Semble access credential |
| `webhook_id` | Semble subscription identifier |
| `encrypted_webhook_secret` | Secret used to verify webhook signatures |
| `settings` | Approved configuration values |
| `last_health_check_at` | Connection-health record |
| `last_success_at` / `last_failure_at` | Operational monitoring |

### 7.2 `semble_patient_links`

| Field | Purpose |
| --- | --- |
| `customer_flow_case_id` | Internal case relationship |
| `customer_flow_patient_id` | Persistent Customer Flow patient relationship |
| `semble_patient_id` | Semble source record |
| `link_status` | Linked, pending_review, conflict, deleted, unlinked |
| `match_method` | Manual, exact, reviewed_suggestion, created |
| `matched_at` / `matched_by` | Audit and accountability |
| `last_synced_at` | Freshness information |

One Semble patient may relate to more than one Customer Flow case. The mapping should therefore support patient-level and case-level references rather than enforcing a one-case-to-one-patient rule.

### 7.3 `semble_document_links`

| Field | Purpose |
| --- | --- |
| `customer_flow_photo_id` | Original Customer Flow photo |
| `semble_document_id` | Created Semble document |
| `customer_flow_case_id` | Handover context |
| `source_checksum` | Deduplication guard |
| `uploaded_at` | Audit information |
| `file_name` | Semble-facing document name |

### 7.4 `semble_sync_jobs`

| Field | Purpose |
| --- | --- |
| `job_type` | Match, create_patient, export_summary, upload_document, refresh_booking, reconciliation |
| `idempotency_key` | Prevents duplicate effects |
| `subject_type` / `subject_id` | Case, patient, photo, booking, or event |
| `state` | Queued, processing, succeeded, retrying, failed, blocked |
| `attempt_count` / `next_attempt_at` | Controlled retry policy |
| `request_summary` / `response_summary` | Sanitised diagnostics; never store raw secrets |
| `error_code` / `error_message` | Failure actionability |

### 7.5 `semble_webhook_events`

| Field | Purpose |
| --- | --- |
| `connection_id` | Which practice received the event |
| `event_id` | Semble event identity, when provided |
| `event_type` | Example: `booking.updated` |
| `resource_id` | Semble identifier to refresh |
| `received_at` | Delivery timing |
| `signature_valid` | Security/audit outcome |
| `payload_hash` | Duplicate detection without retaining unnecessary raw data |
| `processing_state` | Received, processed, ignored, failed |

## 8. Patient matching and linking

### 8.1 Matching principle

The connector should prefer a pre-existing stored Semble patient ID. If none exists, it may search Semble but must not auto-link a non-exact or uncertain result.

### 8.2 Initial matching rules

| Confidence | Criteria | Result |
| --- | --- | --- |
| High | Exact configured combination, such as verified email plus date of birth | Suggest link; optional automatic link only after pilot approval |
| Medium | Same full name plus date of birth, or verified phone plus name | Admin review required |
| Low | Name only, partial phone, or multiple matches | Do not link; require admin review or create new patient |
| None | No result | Offer create-patient action |

Do not use a pure name-only match. Patient identity mistakes are more harmful than an extra manual review.

### 8.3 Admin resolution choices

An admin must choose one of:

1. Link to selected Semble patient.
2. Create a new Semble patient from the Customer Flow intake data.
3. Leave unlinked and return later.
4. Mark as duplicate/conflict for clinic staff to resolve in Semble.

Customer Flow must not call Semble's merge capability. Semble’s authorised-user merge process remains the safe path for patient-record merging.

### 8.4 Patient creation payload

Phase 2 should export only fields that are necessary and consented for clinic administration:

- First and last name.
- Date of birth.
- Sex/gender only if the Semble patient schema and clinic policy require it.
- Phone and email.
- Address/city where appropriate.
- Customer Flow case reference as an external/reference field or approved custom attribute.

Agency name, occupation, free-text internal discussion, and medical recommendation must not be sent as demographic data. They belong in an intentional consultation summary or clinic-approved note.

## 9. Consultation-summary export

### 9.1 Handover trigger

Initial pilot default: **Manual admin action**.

After pilot acceptance, enable a configurable automatic trigger only at one approved workflow point:

- Confirmed, or
- Booked.

Do not hand over every newly created or doctor-answered case by default. This keeps Semble free of abandoned leads and protects patient-data minimisation.

### 9.2 Summary contents

The summary must be a dated, immutable handover snapshot:

- Customer Flow case reference and patient ID/reference.
- Submission date and agency/referral source, if clinic policy permits.
- Latest doctor assessment text.
- Approximate grafts and recommended price as readable text.
- Current Customer Flow consultation status.
- Photo/document list exported in this handover.
- Link or reference to the Customer Flow case, where permitted.

Structured graft and price values must remain in Customer Flow because Semble custom data is free text rather than a dedicated typed field. Any Semble custom-attribute content is treated as a readable snapshot, not as data to calculate against.

### 9.3 Re-export rules

- The first successful handover creates the snapshot.
- A later explicit **Send updated consultation summary** action creates a versioned follow-up rather than overwriting historical information.
- Re-export requires a reason/action label: amended recommendation, additional photos, booking preparation, or manual correction.

## 10. Photo/document export

### 10.1 Eligibility

Only export photos that are:

- Attached to the linked Customer Flow case.
- Not deleted.
- Permitted by the configured photo-export policy.
- Available in their original or approved processed version.

Exclude transient preview files, thumbnails, and unsupported annotation work-in-progress.

### 10.2 Naming convention

Use a deterministic filename so Semble users can understand the origin and the connector can safely recover from retries.

`CF-{case-reference}-{category}-{sequence}-{YYYYMMDD}.{extension}`

Examples:

- `CF-HT-240946-CONSULTATION-01-20261002.jpg`
- `CF-HT-240946-ANNOTATED-01-20261002.jpg`

### 10.3 Upload sequence

For each eligible photo:

1. Confirm no successful `semble_document_link` already exists for the same photo/checksum and patient.
2. Create the Semble patient-document record.
3. Receive the returned upload URL.
4. Upload the binary file to that URL.
5. Confirm the document creation/upload result according to Semble’s response model.
6. Persist the Semble document ID, filename, checksum, and timestamp.

The process must handle one document at a time and queue bulk work. A failed document must not cancel successful exports for other photos.

### 10.4 Failure states

- Missing/deleted source photo: block that job and display action needed.
- Expired upload URL: create a new document/upload attempt only if no successful document link exists.
- Network/rate-limit failure: retry with backoff.
- Permanent Semble validation failure: stop retrying and show the exact admin-facing resolution message.

## 11. Incoming webhooks

### 11.1 Minimum initial subscriptions

Start with only events that change a Customer Flow user’s operational view:

- `patient.updated`
- `patient.deleted`
- Relevant `booking.created`, `booking.updated`, and cancellation events
- Relevant `episode` or `pathway` events, if the clinic uses them
- `patient document` events only if they support an agreed Customer Flow display purpose

Exact event strings and record identifiers must be confirmed against the connected Semble schema. Semble requires each desired event type to be registered explicitly. [Webhook guide](https://docs.semble.io/docs/webhooks/guide/)

### 11.2 Receiver flow

1. Receive the HTTPS POST request.
2. Read the raw body without parsing or serialising it first.
3. Verify Semble’s `X-Webhook-Signature` using the stored webhook secret and the timestamp/raw-body signing format.
4. Reject an invalid signature with `401` or `403`.
5. Apply replay-window and duplicate checks.
6. Store a minimal event receipt and enqueue asynchronous processing.
7. Return a successful acknowledgement promptly after secure receipt.
8. Worker fetches the current Semble record using the event resource identifier.
9. Update only the approved Customer Flow operational projection.
10. Mark the event processed, ignored, or failed with a reason.

Semble signs each webhook with HMAC-SHA256 and documents verification over `<timestamp>.<raw_request_body>`. [Signature verification](https://docs.semble.io/docs/webhooks/guide/)

### 11.3 Ordering, duplicates, and idempotency

Do not assume that webhooks are unique or ordered.

- Deduplicate by Semble event ID where available; otherwise use event type, resource ID, timestamp, and payload hash.
- Fetch the current Semble resource after event receipt rather than trusting the webhook as a complete source record.
- Ignore a stale projection update when the fetched Semble resource is older than the stored Semble version/timestamp.
- Make document exports idempotent by original Customer Flow photo ID plus content checksum.
- Make patient creation idempotent by case/patient mapping and an internal immutable handover identifier.

Semble retains webhook logs for 30 days, retries failed deliveries, supports replay, and may pause a failing subscription. The connector must therefore include both automated retry and operator recovery paths. [Webhook delivery recovery](https://docs.semble.io/docs/webhooks/guide/)

## 12. Customer Flow operational projection

Add a separate integration panel/status to linked cases. It must not alter existing consultation statuses.

| Semble signal | Customer Flow integration display | Existing case state changed? |
| --- | --- | --- |
| Patient link established | Linked to Semble | No |
| Document export completed | Documents synced | No |
| Booking created/confirmed | Semble booking confirmed | No |
| Booking rescheduled | Semble booking date updated | No |
| Booking cancelled | Semble booking cancelled | No |
| Pathway/episode stage changed | Semble treatment stage updated | No |
| Patient deleted/unavailable | Semble link needs review | No |
| Webhook/sync error | Semble sync needs attention | No |

The admin may later choose a policy that an approved Semble booking confirms the Customer Flow case. That would be a separate, explicitly approved workflow change, not a side effect of the connector.

## 13. Security, privacy, and retention

### Required controls

- Encrypt Semble API tokens and webhook secrets at rest using the server’s existing secret-management approach.
- Redact tokens, secrets, signed headers, upload URLs, and unnecessary personal data from logs.
- Use HTTPS for webhook delivery and all Semble API calls.
- Verify webhook signatures using a constant-time comparison.
- Enforce a replay window and preserve a compact duplicate-detection record.
- Restrict connector configuration and retry operations to administrators.
- Use permission-scoped Semble tokens, not a personal clinician login token.
- Keep a separate audit trail for manual link selections and exports.
- Define retention for webhook payload metadata and connector diagnostics consistent with the clinic’s data-protection policy.

### Data minimisation

- Export the smallest patient and consultation dataset required for the selected Semble operation.
- Do not include Customer Flow internal messages in Semble by default.
- Do not copy payment information into Customer Flow.
- Do not expose Semble patient-directory search to non-admin Customer Flow users.
- Keep Customer Flow and Semble photo copies governed by each system’s retention and access controls.

## 14. Rate limiting and queue policy

Semble has advised a limit of 240 API requests per minute per query. The connector must use a queue regardless of the apparent capacity.

Initial controls:

- A per-practice request limiter below the published allowance, with room for normal Semble UI/API usage.
- Sequential or small-concurrency document uploads per patient/case.
- Exponential backoff for temporary failures and rate-limit responses.
- A maximum retry count followed by **Needs attention** rather than indefinite retries.
- Daily scheduled reconciliation for recently changed, linked records.
- Manual retry only for authorised admins.

## 15. Admin monitoring and recovery

### Connector dashboard

Show:

- Connection state and environment.
- Last successful API call and webhook.
- Last failure and meaningful remediation message.
- Number of queued, retrying, failed, and blocked sync jobs.
- Recent patient links, photo exports, and booking updates.
- Webhook subscription status, including delivery-paused warning.

### Actions

- Test connection.
- Pause or resume outbound handovers.
- Reconnect/rotate credential.
- Re-register or resume webhook subscription.
- Retry a job.
- Re-fetch a linked Semble patient or booking.
- Resolve a patient-match conflict.
- Unlink a case from Semble only with an audit reason; this does not delete either patient record.

## 16. Delivery phases

### Phase 0 — Discovery and agreement

**Goal:** confirm that the connected Semble package and sandbox expose the precise required operations.

Deliverables:

- Sandbox practice and scoped sandbox token.
- Confirmation of available patient search/create, patient document, booking, episode/pathway, and webhook mutations/events.
- Agreed patient identity matching rules.
- Agreed multi-day surgery model.
- Approved data-protection and access policy.
- Final selected integration statuses and handover trigger.

Exit criteria: a signed-off field map and a sandbox test checklist.

### Phase 1 — Connector foundation and read-only linking

**Goal:** establish a safe connection without automatic writes.

Deliverables:

- Admin connection settings and encrypted credentials.
- Connection health check.
- Patient lookup by known Semble ID.
- Manual patient-match review UI.
- Mapping, audit, job, and webhook-event storage.
- Connector dashboard and failure states.

Exit criteria: an admin can connect to sandbox, link a Customer Flow patient to an existing Semble patient, and see auditable status.

### Phase 2 — Controlled one-way handover

**Goal:** safely send approved consultation data to Semble.

Deliverables:

- Manual **Send to Semble** action.
- Patient creation after admin decision.
- Consultation-summary export.
- Selected photo/document export.
- Per-document results and retry controls.

Exit criteria: a real sandbox case can create/link a Semble patient, upload selected documents, and leave a complete audit trail with no duplicate export after retry.

### Phase 3 — Secure inbound operational updates

**Goal:** show selected Semble booking/journey progress in Customer Flow.

Deliverables:

- HMAC-verified webhook receiver.
- Event receipt, duplicate prevention, and queue processing.
- Booking/pathway display projection.
- Paused-webhook monitoring and recovery guide.
- Reconciliation routine for linked records.

Exit criteria: a Semble sandbox booking update reaches Customer Flow once, shows the correct operational state, and cannot change the core consultation status unexpectedly.

### Phase 4 — Selective automation

**Goal:** reduce manual work after the pilot proves safe.

Possible deliverables:

- Configurable automatic handover on confirmed or booked status.
- Versioned updated consultation-summary exports.
- Configurable document category/folder/naming rules.
- Optional clinic reporting using mapping and sync status.

Exit criteria: explicit clinic approval following pilot metrics and data-quality review.

## 17. Sandbox acceptance test plan

| Test | Expected result |
| --- | --- |
| Token environment | Sandbox token succeeds only against sandbox endpoint |
| Minimal permission scope | Connector can perform enabled operations but cannot query/write unapproved Semble areas |
| Existing patient link | Exact known Semble patient links without duplicate creation |
| Ambiguous patient | Connector requires admin decision and does not auto-link |
| New patient | Admin-approved creation stores Semble ID and Customer Flow reference |
| Summary export | Readable summary appears on the intended Semble patient record |
| One photo export | Document appears once with expected filename and mapping record |
| Partial photo failure | Other photos succeed; failed photo is retryable without duplicates |
| Webhook signature | Valid event processes; tampered or stale request is rejected |
| Duplicate webhook | Event is ignored safely after first successful processing |
| Booking update | Customer Flow integration status changes; consultation workflow does not |
| Retry recovery | Temporary API/network failure retries and succeeds once |
| Pause/replay | A failed Semble delivery can be replayed without duplicate projection |
| Disconnect | Customer Flow cases continue operating normally while connector is disabled |

## 18. Open decisions requiring clinic approval

1. Which Customer Flow milestone enables handover: manual only, confirmed, or booked?
2. Which patient fields may be exported and later refreshed?
3. What exact field combination constitutes a safe automatic patient match, if any?
4. Are agency/referral source and internal notes permitted in the Semble handover summary?
5. Which photos are eligible: originals, annotated images, or both?
6. Should annotated photos be represented as a separate Semble document category?
7. Which Semble booking and pathway states should be visible to agents and doctors versus admins only?
8. How will multi-day surgery be modelled: separate bookings, episode, pathway, or a clinic-specific combination?
9. Which Semble users/locations/booking types represent the hair-transplant clinical workflow?
10. What should Customer Flow do when Semble identifies a potential duplicate patient?
11. What data-retention period applies to connector logs and mapping records?
12. Who receives integration-health alerts and who is authorised to replay or resume webhooks?

## 19. Pre-build checklist

- [ ] Semble subscription/package confirms API and webhook access.
- [ ] Semble enables webhooks for the practice.
- [ ] Sandbox practice, token, and sample patients are available.
- [ ] Required API permissions are defined and applied.
- [ ] Test doctor, location, booking type, and procedure configuration are identified.
- [ ] Clinic chooses multi-day surgery model.
- [ ] Data-processing and privacy review is approved.
- [ ] Field ownership and conflict rules are signed off.
- [ ] Handover trigger and photo policy are signed off.
- [ ] Customer Flow host has an HTTPS webhook endpoint available.
- [ ] Technical-contact email is set in Semble for webhook pause notifications.

## 20. Source material

- [Semble Public API overview](https://docs.semble.io/docs/intro/)
- [Semble authentication and environments](https://docs.semble.io/docs/authentication/)
- [Semble webhook guide](https://docs.semble.io/docs/webhooks/guide/)
- Semble support responses supplied by the Customer Flow team: custom attributes, patient documents/photos, multi-day surgery, migration, rate limits, costs, and international patients.
