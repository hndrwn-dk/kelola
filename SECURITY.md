# Security Policy

## Reporting a vulnerability

Email **support@tursinalabs.com**.

Do not open a public GitHub issue for anything that could lock an operator out of a host, leak key material, bypass TOFU pinning, or run an unexpected command on a managed machine.

Please include:

- Kelola version (`v0.1.0` or the git SHA)
- Device and OS (Android / iOS)
- Affected host OS only if it matters, with secrets redacted
- Steps to reproduce, or a patch

## Response SLA

Times are business days, UTC+8.

| Step | Target |
|---|---|
| Acknowledge receipt | 2 days |
| Initial assessment (in scope / severity / next step) | 5 days |
| Fix or mitigation plan for a confirmed issue in the latest release | 14 days |

If a patch needs coordinated disclosure, we will agree a date with you. We do not pay a bug bounty.

## Scope

In scope: hardware-backed key handling, SSH TOFU / host-key mismatch, probe command construction, lockout guards, sudo hints, audit/log redaction, and secrets appearing in the UI, backups, or logs.

Out of scope: an already-compromised host, weak sudoers the operator wrote, and social engineering of the phone user.
