# Patient Intake and Agency Embedding Plan

## Goal

Let a patient submit one hair-transplant enquiry that is immediately available to both the referring agency and the clinic. Remove the agency's duplicate data-entry and photo-upload work while preserving first-source ownership.

## Delivery stages

### 1. Public intake foundation — implemented

- Agency-specific forms with optional doctor assignment.
- Direct links, iframe snippets and responsive JavaScript embed snippets.
- Domain allow-list support through `frame-ancestors` CSP.
- Public form configuration and submission endpoints.
- Required full name, consent, and at least one of email or phone.
- Secure two-hour upload sessions with JPEG, PNG and HEIC signature validation.
- Mobile-friendly form and camera/file upload.

### 2. Patient matching and ownership — implemented

- Global matching by normalized email and phone.
- A new application is created for each agency submission while a confidently matched patient is reused.
- First source remains the owner when another agency submits the same patient.
- Source agency, current owner, match basis and consent time are retained separately.
- Admin-only transfer with a mandatory reason, audit event and transfer history.
- Transfer moves active case access to the new owning agency while preserving original source records.

### 3. Agency operations — implemented for web

- Agents see only forms for their agency.
- Admins see all forms; managers have read-only access.
- Links and embed snippets can be copied from the web workspace.
- Forms can be paused and reactivated.
- Public submissions enter the existing case, notification and live-update workflow.

### 4. Patient account — implemented

- Email-only username with password and verified one-time access code.
- An account is linked to an intake record only after email verification.
- Patient-scoped case, photo and follow-up note access; internal clinical and pricing notes stay private.
- Seven-day sessions, sign-out and password recovery through a new access code.
- The shared login screen recognizes patient email accounts and redirects to the patient portal.

### 5. Production hardening — next

- Persistent rate limiting and abuse protection for public endpoints.
- Upload malware scanning and storage lifecycle policy.
- Consent text versioning and configurable privacy links.
- Delivery monitoring for verification email/SMS.
- Verified email-change workflow for patient accounts.
- Metrics for form views, starts, completions and source conversion.
- End-to-end browser coverage across direct, iframe and JavaScript embedding.

## Ownership rules

1. The first confirmed source agency owns the patient relationship.
2. Later submissions remain attributable to their own source agency but do not overwrite ownership.
3. Only an administrator can transfer ownership.
4. A transfer requires a reason and never rewrites the original source or audit history.
5. Agencies never receive information about another agency's submission through the public form.
