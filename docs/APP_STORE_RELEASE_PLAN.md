# App Store and Demo Release Plan

## Immediate release goal

- Production APNs credentials have been authenticated against Apple.
- The current iOS Release build has been uploaded to TestFlight and installed
  on a physical iPhone.
- Production device registration is active on the NatChatt staging server.
- Complete an end-to-end Production push delivery check for admin, manager,
  agency users and doctors before App Store submission.

## Public demo server

- Deployment workspace: `/Users/drascom/Documents/work/oracle/stage/`
- Public address: `https://flow-demo.drascom.uk`
- The separate Customer Flow server and database were deployed on 17 August
  2026 and are managed by `customer-flow-demo.service`.
- The service listens on NetBird destination `http://100.111.58.102:8080` and
  is exposed publicly only through the HTTPS proxy.
- Health check: `https://flow-demo.drascom.uk/api/v1/health`
- Web client: `https://flow-demo.drascom.uk/admin/`
- Keep the service available throughout TestFlight Beta App Review and App
  Store Review.
- Use only fictional patients, public-domain or purpose-made images, and sample
  conversations. Never copy staging or production patient data.
- Create dedicated review accounts that cover the admin, agent and doctor
  workflows. Store credentials in App Store Connect Review Information, not in
  this repository.
- Current review usernames are `admin`, `user1` and `doctor1`; passwords remain
  only in the protected server environment and App Store Connect Review
  Information.
- The demo deployment intentionally has no NatChatt APNs private key. Realtime
  updates and in-app notifications remain available; external Apple push is
  verified on the separate NatChatt staging deployment.
- Verify login, case creation, photo upload, doctor response, agent
  confirmation, realtime updates and role-scoped notifications before each
  submission.

## App Review positioning

Customer Flow is a genuinely open-source, self-hosted consultation workflow.
The iOS app is a general client that can connect to any compatible Customer
Flow server; it is not limited to NatChatt or to one customer organisation.
Anyone can download the server, install it, create local users and connect the
iOS app to that server.

Suggested Review Notes:

> Customer Flow is an open-source, self-hosted consultation workflow for
> clinics, authorised agencies and doctors. The iOS application can connect to
> any compatible Customer Flow server selected by the user. It is not limited
> to NatChatt or to a single customer organisation. For App Review, we provide
> a continuously available demonstration server at
> https://flow-demo.drascom.uk together with dedicated review accounts and
> fictional sample data. The public source repository and server installation
> instructions are provided in the Review Information. No real patient data is
> present on the demonstration server.

Also state in Review Information:

- the server URL and the purpose of each supplied review account;
- the exact path through the admin, agent and doctor flows;
- that accounts are created by each self-hosted server administrator, so the
  public client does not provide a NatChatt account-registration service;
- that in-app notifications and realtime updates are part of the open-source
  server;
- that Production push delivery is available only on deployments configured
  with an authorised APNs provider and is not required for core operation;
- the public privacy-policy URL, support URL and source repository URL.

## Security and distribution boundaries

- Never publish or distribute NatChatt's APNs `.p8` private key.
- The official NatChatt-managed deployment may use the official app's APNs
  credentials.
- Community installations continue to support realtime and in-app
  notifications without NatChatt operating a free push relay.
- A developer who forks and signs a custom iOS build must use their own bundle
  identifier and Apple credentials.
- Keep API keys, databases, uploaded media and review credentials outside Git.

## Submission checklist

- Provide a working demo account or fully functional demo mode.
- Keep all submitted URLs live and remove placeholder content.
- Ensure screenshots show the actual app rather than only login or splash
  screens.
- Complete privacy disclosures for patient details, photos, contact details
  and user-generated consultation content.
- Confirm the support and privacy-policy pages are publicly accessible.
- Confirm the Release build number is unique and the minimum-version policy is
  not blocking the submitted build.
- Test the exact archived build through TestFlight before App Store submission.
