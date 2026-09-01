# Kelola

Agentless Linux administration from a phone. If the host runs `sshd`, Kelola can reach it. Nothing is installed on the server.

Kelola is a Flutter client (Android and iOS) from Tursina Labs. It SSHs in with a hardware-backed key, discovers what the machine is, and exposes admin as structured screens — not a terminal with a coat of paint.

**Target hosts:** homelab boxes, VPS, cloud VMs, small on-prem fleets. Any distro with OpenSSH.

**Not (v1):** a monitoring product, an Ansible replacement, a multi-user team tool, or a cloud account. There is no Tursina backend and no telemetry.

## How it works

1. The phone generates an ECDSA P-256 key in **Android StrongBox** or **iOS Secure Enclave**. The private key is non-exportable; signing is biometric-gated.
2. Enrollment shows a QR code and an `authorized_keys` line. You paste that on the host by any means — USB, another SSH session, a console. No network from the phone is required for enrollment.
3. First connect pins the host key (TOFU). A mismatch is a hard block.
4. One batched SSH command discovers OS, init, package manager, firewall, and journal access (`HostFacts`). The dashboard then shows load, memory, disk, and failed units.
5. Every command is a typed **Probe** (`read` / `mutate` / `destructive`), dispatched through a session pool, and written to a local audit log. Root login is refused.

One hardware key per phone, reused for every host. That is intentional.

## What works today

| Area | Status |
|---|---|
| Hardware SSH identity (StrongBox / Secure Enclave) | Working on physical Android |
| Host inventory, ssh_config import (IdentityFile ignored) | Working |
| Enrollment QR + TOFU host-key pinning | Working |
| HostFacts + dashboard | Working against Ubuntu/OpenSSH |
| systemd unit list, detail, start/stop/restart/enable/disable | Working; OpenRC lists without crashing |
| Self-lockout guard on SSH/network units | Working |
| Password sudo | Detected and refused (`sudo -n`); no hang |

Still ahead (see [`readiness/MILESTONES.md`](readiness/MILESTONES.md)): journald, audit UI, containers, SFTP, incident sheets, tunnels, packages/firewall/disk, terminal, fleet, NAT.

Specs: [`readiness/SPEC.md`](readiness/SPEC.md) · design: [`readiness/DESIGN.html`](readiness/DESIGN.html) · M0 decision: [`readiness/M0-GO-NO-GO.md`](readiness/M0-GO-NO-GO.md).

## Host requirements

| Need | Notes |
|---|---|
| `sshd` | Already on every Linux distro |
| Public key in `~/.ssh/authorized_keys` | One line from the enrollment screen |
| A non-root sudoer | Kelola will not log in as `root` |
| Passwordless sudo (optional) | Required for mutate actions; Kelola never prompts for a sudo password |
| `systemd-journal` group (optional) | Sudo-free log reads, later milestone |

From the phone, use the host's **LAN or public IP**. `10.0.2.2` is emulator-only.

## Run

Flutter 3.47 / Dart 3.13. A physical device is required for StrongBox; the iOS simulator falls back to a software key and labels it.

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

Package id: `labs.tursina.kelola`.

## Layout

```
lib/
  domain/          probes, HostFacts, units, risk, ssh_config import
  data/keystore/   platform channel to StrongBox / Secure Enclave
  data/ssh/        DER converter, dartssh2 identity, session pool, TOFU
  data/db/         Drift: hosts, facts, pins, recents, audit
  presentation/    screens and design-system widgets
android/           HardwareSignerPlugin.kt
ios/               HardwareSignerPlugin.swift
test/              parser fixtures for Ubuntu, Debian, Rocky, Alpine
readiness/         product spec and milestone plan
```

## Security notes

- No password authentication. Ever.
- Cipher/KEX allowlist is modern-only (ChaCha20, AES-GCM, AES-CTR, curve25519, ECDH P-256). No SHA-1, no CBC.
- Stopping `sshd` or a network unit requires typing the host alias.
- Private keys never appear in logs, backups, or the UI. Restoring inventory on a new phone means re-enrollment.
