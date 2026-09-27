# M30 — Background fleet watch

Pro unlock convenience: periodic read-only fleet refresh with user
thresholds and a local notification. No server, no account.

Full design: `docs/superpowers/specs/2026-09-27-m30-fleet-watch-design.md`.

## Rules

- Drive `FleetHealthProbe` through `ProbeScope.fleet` so
  `assertFleetReadOnly` still holds.
- Entitlement is checked in the scheduler and Settings, never in
  `lib/domain/fleet`.
- Promise roughly hourly. Never advertise a 15-minute cadence.
- Reuse `assessFleetHost` with user thresholds. Do not invent a second
  severity table.
- Notify once per host per fingerprint change. First tick is baseline
  only.
- Own notification channel `kelola_fleet`, not the tunnel FGS channel.
- Only hosts in the user's fleet probe selection. Writes `fleet_cache`
  and the home widget snapshot.
- Default off.
