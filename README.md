# Customer Flow

Customer Flow is a self-hosted clinical consultation workflow for clinics, authorised agents and doctors. Agents create patient cases with notes, estimates and photos; doctors review the cases and send clinical recommendations; administrators manage users, agencies, assignments and reporting access.

The project is designed for organisations that need a private, role-based consultation flow without using a public registration system.

## Components

- [`api/`](api/) — Python API, authentication, SQLite storage and uploaded-media handling.
- [`admin-panel/`](admin-panel/) — Responsive web administration interface served by the API.
- [`ios-app/`](ios-app/) — Native SwiftUI app for Doctor, Agent and Admin users.
- [`docs/`](docs/) — Project plan and interface mockups.

## Important

The iOS app is a client and **does not work without a running Customer Flow server**. On first launch, the user enters the server address and then signs in with an account created by an administrator. There is no public sign-up screen.

The included automatic server installer targets a **Linux machine running systemd**. It registers the API as a system service, starts it immediately and enables automatic startup after reboot. Other operating systems can be used for development, but require manual startup.

For production use, the server must be placed behind HTTPS and configured with secure passwords, protected storage, backups and SMTP for password recovery. Patient photos and the SQLite database are intentionally excluded from this repository.

## Quick start

1. Install and start the [API](api/README.md).
2. Review the [admin panel](admin-panel/README.md) setup.
3. Open and run the [iOS app](ios-app/README.md).
4. Enter the reachable server address in the app and sign in with a server-created account.

This software supports consultation workflow and record handling. It does not replace professional medical judgement or local clinical, privacy and regulatory obligations.
