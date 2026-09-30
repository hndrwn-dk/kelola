# Play Console — release notes (0.2.7)

**Version name:** 0.2.7  
**Version code:** 10  
**Track:** Alpha (or Internal)  
**AAB:** `bundles_release/v0.2.7+10/app-release-0.2.7+10.aab` (gitignored; local only)

**Play paste:** `bundles_release/play-console/PLAY_STORE_v0.2.7+10.txt`

## Short description (Play “Release notes”, en-US)

Full-screen terminal (vim, top, less), jump-host chains, encrypted vault export, and Kubernetes YAML apply on the host. Package listing and SFTP errors are honest on Rocky. App lock and SSH keys fail closed; OpenAI-compatible Assist requires HTTPS.

## Longer notes (optional / changelog)

What’s new in 0.2.7 (since 0.2.6+9):

- **Terminal** — Full-screen PTY so vim, top, and less work on the host.
- **Jump hosts** — Multi-hop chains, via labels, first-connect through a bastion.
- **Vault** — Encrypted export/sync. Existing SSH host-key pins are not overwritten; env values and snippet templates stay off the blob unless you include secrets. Import never turns on agent forwarding.
- **Host env / snippets** — Per-host and tag environment bindings. Snippet multi-exec with per-host preview.
- **SSH** — Optional StrongBox agent forwarding (off until you confirm). OpenSSH user certificates bound to the phone key. Enrollment shows when presence is required. Android never creates an unauthenticated Keystore key.
- **Kubernetes** — Guarded `kubectl` YAML apply with a server-side diff.
- **Compose / logs / fleet** — Compose stack actions, local session logs with journal bookmarks, background fleet watch with hourly local alerts.
- **Tunnels** — SOCKS5, remote forward, and kubectl port-forward.
- **Packages / Files** — Rocky `dnf` check-update over SSH no longer hangs or lies. SFTP permission denials are named instead of looking like a broken path.
- **Chrome** — Amber arcs on every full-page host tool.
- **Lock / Assist** — App lock stays locked on platform errors (not only cancel). iOS Recents hide the inventory while lock is on. OpenAI-compatible API keys require HTTPS (loopback HTTP only).
- **Release** — WorkManager constructors survive AGP 9 R8 so the release binary launches.

## Play App content — FGS

If not already submitted for this package: paste from `docs/play/fgs-declaration.md` (specialUse justification, impact if deferred/interrupted, demo shot list).

## Build

```bash
# Requires pubspec_overrides.yaml pointing kelola_pro at the private billing
# package. The check refuses a std-stub AAB (all Pro unlocked).
bash scripts/build_play_aab.sh
```

Signed with `android/key.properties` → upload keystore.

Do **not** run bare `flutter build appbundle --release` for Play — that skips the billing gate.
