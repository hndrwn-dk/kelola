# Play Console — release notes (0.2.4)

**Version name:** 0.2.4  
**Version code:** 6  
**Track:** Alpha (or Internal)  
**AAB:** `bundles_release/v0.2.4+6/app-release-0.2.4+6.aab` (gitignored; local only)

## Short description (Play “Release notes”, en-US)

Local SSH tunnels: open Cockpit, Portainer, Grafana, and other host UIs in your phone browser through a loopback-only forward. Idle tunnels close automatically; an ongoing notification lists active tunnels with Stop all.

## Longer notes (optional / changelog)

What’s new in 0.2.4:

- **Tunnels** — SSH local port forwarding with named presets (Cockpit, Portainer, Grafana, Prometheus, Custom), saved targets per host, and open-in-browser.
- Loopback-only listeners (`127.0.0.1`, ephemeral port). HTTP and HTTPS warnings explain plaintext-on-device vs SSH encryption and expected certificate mismatch at 127.0.0.1.
- Active tunnel list across hosts with filters, channel count, idle countdown, Retry/Dismiss on failure.
- Idle auto-close when no forwarded connections remain (default 10 minutes); Keep-alive on the tunnel SSH session.
- Android foreground service (`specialUse`) while tunnels are active, with Stop all.
- Database schema 13: saved tunnel targets; audit close reasons for tunnel open/close.

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
