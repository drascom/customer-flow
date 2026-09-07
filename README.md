# Customer Flow by NatChatt

Customer Flow is a self-hosted clinical consultation workflow for clinics, authorised agents and doctors. Agents create patient cases with contact and location details, consultation needs, estimates and photos; doctors review the cases and send clinical recommendations; managers and administrators oversee the operational workflow.

The project is designed for organisations that need a private, role-based consultation flow without using a public registration system.

## Workflow highlights

- Create and update patient consultations with at least one photo.
- Keep address, city and region as separate patient details.
- Review, enlarge and annotate patient photos.
- Continue role-aware conversations between agents, doctors and managers.
- Record final graft and price recommendations and confirm an appointment date and time.
- Close finished conversations without requiring both sides to close them; a new message reopens the conversation automatically.
- Receive realtime dashboard updates and in-app notifications.
- Connect an agency's own system through the optional, agency-scoped MCP integration.

## Components

- [`api/`](api/) — Python API, authentication, SQLite storage and uploaded-media handling.
- [`admin-panel/`](admin-panel/) — Responsive web dashboard for Agent, Doctor, Manager and Admin users, served by the API.
- [`ios-app/`](ios-app/) — Native SwiftUI app for Agent, Doctor, Manager and Admin users.
- [`mcp-server/`](mcp-server/) — Least-privilege MCP connector for agency LLM and automation systems.
- [`docs/`](docs/) — Project plan and interface mockups.

## Important

The iOS app is a client and **does not work without a running Customer Flow server**. On first launch, the user enters the server address and then signs in with an account created by an administrator. There is no public sign-up screen.

The iOS client is also available on the
[App Store](https://apps.apple.com/gb/app/customerflow-by-natchatt/id6802274147).

For production use, the server must be placed behind HTTPS and configured with secure passwords, protected storage, backups and SMTP for password recovery. Patient photos and the SQLite database are intentionally excluded from this repository.

## Public demo

A continuously available disposable demo is hosted at
<https://flow-demo.drascom.uk>. The same responsive client is available at
<https://flow-demo.drascom.uk/admin/>.

Use either of these accounts:

- Agency user: `user1` / `demo123`
- Doctor: `doctor1` / `demo123`

The demo contains fictional seed data. Its database, uploaded media, sessions
and notifications are erased and recreated **at the start of every hour**.
Active demo sessions are signed out during each reset. Never upload real
patient, personal or confidential information. Realtime updates and in-app
notifications work in the demo; external Apple push delivery is not enabled
there.

## Quick start

1. Install and start the [API](api/README.md).
2. Review the [web dashboard](admin-panel/README.md) setup.
3. Open and run the [iOS app](ios-app/README.md).
4. Enter the reachable server address in the app and sign in with a server-created account.

Agencies that want to connect an external workflow or automation system can
also configure the optional [MCP connector](mcp-server/README.md). MCP access is
scoped to a single agency, and write/photo tools remain opt-in for each server
deployment.

For lock-screen and background notifications, complete the
[Production APNs setup](api/README.md#production-apns-setup) after the API is
running. In-app and dashboard notifications work without an Apple key.

This software supports consultation workflow and record handling. It does not replace professional medical judgement or local clinical, privacy and regulatory obligations.

## Privacy and support

- [Privacy Policy](PRIVACY.md)
- [Support and issue reporting](https://github.com/drascom/customer-flow/issues)
