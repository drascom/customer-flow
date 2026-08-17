# Customer Flow Privacy Policy

**Effective date:** 17 August 2026

Customer Flow is an open-source, self-hosted clinical consultation workflow published by NatChatt Ltd. The iOS app is a client that connects to a Customer Flow server selected by the user or their organisation. This policy explains how the app and compatible Customer Flow servers handle information.

## Who controls the information

The organisation operating the Customer Flow server is normally the controller of information stored on that server. NatChatt Ltd does not automatically receive information from independently operated Customer Flow servers.

When the app is connected to a server operated by NatChatt Ltd, NatChatt Ltd is responsible for that deployment. Users of another organisation's server should contact that organisation's administrator about its privacy practices, retention period, and legal basis for processing.

## Information processed

Depending on how a server is configured and how the app is used, Customer Flow may process:

- account information, including username, display name, role, agency affiliation, and authentication/session information;
- patient and case information entered by authorised users, including name, date of birth or age, gender, contact details, address or region, occupation, notes, estimates, status, and clinical consultation information;
- photos and other images selected or captured by a user, including annotations added in the app;
- messages, recommendations, attachments, and other user-generated consultation content;
- technical and operational information needed to provide the service, such as the chosen server address, timestamps, record identifiers, audit information, and error information recorded by the server;
- notification information, including an Apple Push Notification service device token and delivery status when push notifications are enabled.

The app stores the active session credential in the iOS Keychain. The selected server stores case data, uploaded media, account records, messages, and notification records according to that server operator's configuration.

## How information is used

Information is used only to:

- authenticate users and enforce role-based access;
- create, review, update, and manage consultation cases;
- display and annotate clinical photos;
- support messages and collaboration between authorised participants;
- provide realtime updates and notifications;
- maintain security, reliability, and auditability; and
- respond to support, privacy, or security requests.

Customer Flow does not use personal information for advertising, cross-app tracking, or data-broker activity. The official iOS app does not include third-party advertising or analytics SDKs.

## Sharing and service providers

Information is visible to authorised users of the selected Customer Flow server according to their role and agency permissions. A server operator may use hosting, email, backup, or network providers and is responsible for disclosing those providers to its users.

When push notifications are enabled, limited notification delivery information is sent through Apple Push Notification service. Apple processes that information under its own terms and privacy policy.

Customer Flow does not sell personal information.

## Retention and deletion

Each server operator determines its retention and deletion policy. Authorised administrators may remove records where the server provides that function. Some in-app deletion actions are soft deletions so that administrators can retain an audit record.

The public demonstration server at <https://flow-demo.drascom.uk> uses fictional data and automatically resets its database, uploaded media, sessions, and notifications at the start of every hour. **Do not upload real patient, personal, or confidential information to the public demo server.**

To request access, correction, export, or deletion of information on a production server, contact the organisation operating that server. For a NatChatt-operated deployment, use the contact details below.

## Security

Customer Flow supports HTTPS connections, role-based access controls, secure iOS Keychain session storage, and server-managed authentication. No system is completely secure. Server operators are responsible for secure deployment, access management, backups, updates, and compliance with applicable health and privacy laws.

## Children

Customer Flow is intended for authorised professional users and is not directed to children. It does not provide public account registration. Patient information should be entered only where the server operator has a lawful basis and appropriate authority to process it.

## International processing

Information is processed where the selected server and its service providers are located. An organisation operating Customer Flow is responsible for any required international transfer safeguards.

## Changes to this policy

This policy may be updated as Customer Flow changes. Material revisions will be published in this repository with a new effective date.

## Contact

For questions about the official Customer Flow iOS app or a NatChatt-operated deployment, contact:

**NatChatt Ltd**

Email: [drayhancolak@gmail.com](mailto:drayhancolak@gmail.com)

For an independently operated server, contact that server's administrator.
