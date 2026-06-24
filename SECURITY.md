# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report them privately via GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
("Report a vulnerability" under the repository's **Security** tab), or email
**security@otterpace.app**.

We'll acknowledge your report as quickly as we can and keep you updated on the fix.

> Maintainers: update the contact address above to a monitored inbox before
> publishing widely.

## Scope & data handling

Otterpace is **privacy-forward by design**:

- The app is currently local/mock — HealthKit and network/Strava integrations are
  not yet wired into the shipping build, so no user data leaves the device.
- When those integrations land: HealthKit data stays on-device by default, the
  AI coach should receive the minimum necessary context, and users will be able
  to inspect what is sent. There is no account requirement for the MVP.

Reports about data handling, permission scopes, or the (future) coach/Strava
backends are in scope and very welcome.
