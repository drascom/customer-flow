# Semble Integration — Fit Review & Call Prep

As of 2026-09-27

## Summary

Semble is a partial fit. It can be the clinic's system of record for patients, bookings, invoices and deposits, and consent forms. It cannot replace our consultation core: photo annotation, agent–doctor chat and graft recommendations stay in our app.

Recommended model: a one-way sync. When a case is finalized, we create the patient, booking and invoice in Semble. Semble webhooks send booking and payment status back to us.

This review is based on Semble's public docs only. No live API calls have been made yet; that needs a sandbox token.

## Our workflow and Semble basics

**Our workflow today (Customer Flow app)**

1. An agency agent creates a patient (name, date of birth, gender, contact, city/region, occupation).
2. The agent opens a case with at least one photo, a graft estimate and a price quote.
3. A doctor reviews and annotates the photos and discusses the case with the agent in a thread.
4. The case gets final grafts and price, then an appointment date.
5. The case is closed or completed.

We currently have no payment, deposit, operation-day or post-op follow-up records.

**Semble API basics**

- GraphQL API. Production: `https://open.semble.io/graphql`. Sandbox: `https://open.sandbox.semble.io/graphql`.
- Authentication uses an API token created in Semble Settings, sent as the `x-token` header. Tokens can be limited to specific data (patients, bookings, and so on).
- Webhooks cover booking, patient, patient document, invoice, payment on account, questionnaire, episode, pathway and location events. They are signed with HMAC-SHA256 and retried on failure.
- API access is described as free for Semble clinics, but depends on package and role. Rate limits are not documented.

## Capability map

Five of 14 workflow steps are fully supported, seven are partial, and two stay in our app.

| Workflow step | Semble support | How / note |
| --- | --- | --- |
| Create and search patients | Supported | `createPatient`, `patients` search with pagination |
| Doctor assignment | Supported | `users` query; doctor field on bookings |
| Appointment date and time | Supported | `createBooking` (patient, doctor, location, type, start, end) |
| Consent and intake forms | Supported | Questionnaires and `fillQuestionnaire` |
| Live status sync | Supported | Webhooks for booking, patient and document events |
| Region, occupation, agency | Partial | Custom attributes or labels; no agency concept |
| Case photos | Partial | `createPatientDocument` + upload URL; flat list, no series; links expire after 2 hours |
| Graft estimate and final grafts | Partial | Free text, custom attribute or invoice line item; no structured field |
| Price and quote | Partial | Products and invoice line items |
| Multi-day surgery | Partial | One booking per day; episode or pathway grouping untested |
| Deposits (international) | Partial | Payment on account or card payment on a booking; currency support unclear |
| Post-op follow-up schedule | Partial | Recurring bookings, tasks or clinical pathway; no ready-made protocol |
| Photo annotation | Not supported | Stays in our app; annotated image can be uploaded as a document |
| Agent–doctor chat | Not supported | Semble messages patients only (email/SMS); staff chat stays in our app |

## Hair-transplant gaps

Semble is a general clinic system, so our specialty data needs workarounds.

- **Graft count and donor/recipient areas:** no structured fields. They would be custom attributes or free text.
- **Before/after photo series:** photos are a flat document list with no grouping or comparison.
- **Agency partners:** no multi-tenant or partner concept.
- **International patients:** no travel, hotel or transfer data.
- **Staff messaging:** no agent-to-doctor or staff-to-staff chat.
- **Multi-day surgery:** no specialty rules for booking an operation across several days.

## Questions for Monday's call

The first two questions unblock real testing; ask them first.

1. **Sandbox access:** Can we get a sandbox practice with sample data, and how quickly? Can it be reset, and can its webhooks reach our test server?
2. **API token:** Does our package include API access? Can a token be limited to specific data, can we have one per integration, and do tokens expire?
3. **Webhooks:**
    - Which events fire, and do they carry the full record or only IDs?
    - Is delivery order guaranteed?
    - How do retries work, and can we replay missed events after delivery pauses?
    - Do calls come from fixed IP addresses?
4. **Graft and donor-area data:** Are there typed custom fields (numbers, dropdown lists), or could a questionnaire hold this data? Can we filter and report on it?
5. **Photos:**
    - Is there bulk upload?
    - What are the size and file-type limits and the storage quota?
    - Can photos be grouped into before/after series?
    - Is data stored in the UK or the EU?
6. **Multi-day surgery:** Should a 2–3 day operation be one booking, one booking per day, or an episode or pathway? Does the double-booking check also apply when a booking is created?
7. **Migration:**
    - Is there bulk import for existing patients and photos?
    - How are duplicate patients handled?
    - Can we store our own case ID on their records?
8. **Rate limits:** What are the limits, what error comes back when one is hit, and can they be raised during migration?
9. **Cost:** Is the API free on every plan? Are there extra costs for storage, SMS/email, online payments or more than one location?
10. **If time allows:** deposits in several currencies, and keeping each agency's data separate.

## Sandbox test plan

Once Semble gives us a sandbox token, five calls will confirm the core sync works.

**Needed from Semble:** a sandbox practice; an API token with patient, booking, document, invoice and webhook access; a test doctor ID, location ID and booking type ID.

| # | Test | Call | Pass when |
| --- | --- | --- | --- |
| 1 | Authentication | `patients` query, page size 5 | Returns patient list |
| 2 | Create patient | `createPatient` with a Grafts custom attribute | Patient ID returned, attribute saved |
| 3 | Photo upload | `createPatientDocument`, then upload the file to the returned URL | Photo visible on the patient in Semble |
| 4 | Booking | `createBooking` for a full surgery day | Booking appears in the diary |
| 5 | Webhook | `createWebhook` for booking and patient events | Signed event reaches our server, signature verifies |

Exact argument names for `createPatient` and `createWebhook` need confirming against the sandbox schema.

**Sources:** [Semble API docs](https://docs.semble.io/docs/intro/), [Semble API access](https://help.semble.io/api-access)
