# M29 — App lock

OS credential gate in front of the inventory. Full design:
`docs/superpowers/specs/2026-09-21-m29-app-lock-design.md`.

## Why a UI gate, not a crypto gate

StrongBox / Secure Enclave `confirmPresence` already binds destructive
SSH to hardware auth. App lock only hides the inventory (aliases, facts,
dashboards) in Recents and after idle. Tunnels, SFTP, and journal follow
keep running under the overlay.

## Why a new plugin

`HardwareSignerPlugin` authenticates with a `CryptoObject` and
`BIOMETRIC_STRONG` only. App lock must accept the device PIN/pattern
(`BIOMETRIC_STRONG or DEVICE_CREDENTIAL`) and must not touch the SSH
key. `local_auth` is not added; Kelola already ships native plugins.

## Why one settings column

`app_settings.app_lock_timeout_sec` default `0` is Off. That is a
preference, not a secret. No Kelola PIN, no hash, no extra prefs file.

Stored values: `0` off, `-1` immediately, `60` / `300` / `900` minutes.
Any other integer fails open to off.

## Out of scope

B2 billing. Changing `confirmPresence`. Tearing down SSH on lock.
Kelola-owned PIN. Light theme.
