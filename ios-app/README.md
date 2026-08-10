# Customer Flow iOS

Native SwiftUI client for Doctor, Agent, Manager and Admin users. The app connects to a self-hosted Customer Flow server and does not contain a public sign-up flow.

## App Store users

The standard Customer Flow app will be distributed through the Apple App Store. Regular users do not need Xcode or this source repository: they install the app from the App Store, enter the address of their Customer Flow server and sign in with an account created by their administrator.

The App Store app still requires a reachable Customer Flow server and cannot operate as a standalone database.

## Developers

The source code in this `ios-app` folder is provided for developers who want to inspect the implementation, open it in Xcode, make changes or build a customised version of the client.

## Requirements

- macOS with Xcode
- iOS 17 or newer
- A running Customer Flow server reachable from the device or simulator

## Open and develop with Xcode

1. Start the server by following [`../api/README.md`](../api/README.md).
2. Open `CustomerFlow.xcodeproj` in Xcode.
3. Select the `CustomerFlow` target and choose your Apple Development Team under **Signing & Capabilities**.
4. Select an iPhone simulator or connected iPhone.
5. Run the `CustomerFlow` scheme.
6. On first launch, enter the server address, for example `https://flow.example.com`.
7. Sign in with a username and password created by the server administrator.

The app validates `/api/v1/health` automatically. Release builds require HTTPS.

## Included workspaces

- **Doctor:** assigned/waiting queue, search and sorting, multi-photo review, annotation and clinical recommendation.
- **Agent:** case list, guided case creation, duplicate-patient confirmation, updates and Confirm & Close.
- **Admin:** compact mobile case/user management, filters, agencies and doctor assignment.
- **Manager:** read-only access to all users and cases, with doctor assignment as the only management action.
- **Profile:** contact details, password change and role-specific guided tooltips that point to real controls.

Authentication and roles are controlled by the server. Session tokens are stored in iOS Keychain. Password recovery is delivered by the server through SMTP. Push notifications are designed to use APNs through a separate notification adapter.
