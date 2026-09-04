# Hosts inventory + Fleet monitor tiles — design

**Date:** 2026-09-05  
**Status:** approved (chat)

## Split

| Screen | Role |
|---|---|
| **Hosts** | Inventory: add/edit/delete. Alias + IP + OS + health dot + attention **pill**. No metric detail lines. |
| **Fleet** | Monitoring: dense severity-colored **tiles**, progressive fill. All metrics live here. |

## Hosts

- Drop `hostInventoryDetail` (disk% · checked age) from the row.
- Keep `incidentChipLabel` pill; tap → incident sheet (same as Fleet).
- Subtitle stays endpoint (+ OS pretty name); health via `ServiceRow.status` dot.

## Fleet tile probe (one batched exec, no sleep)

Fields: load1/nprocCores, mem%, disk `/` + other mounts >85%, failed units, pending + security count, container trouble (restarting / unhealthy / exited≠0 only), uptime, reboot-required.

**Forbidden:** dual `/proc/stat` + sleep on the tile path.

## Progressive UI

Each host completion `setState`s its tile immediately. First tile ~2s; total 20 hosts ~8–15s must not feel like a blank wait.

## Tap tile → sheet over grid

- Issues from tile data + relevant logs (look up as needed).
- On tap: instant CPU% (dual `/proc/stat`) + top CPU/mem processes.
- ≤2 context actions by priority: failed unit > bad container > critical disk > security updates.
- If more than two issues: show `+N more issues`.
- **Open host** separate navigation control. Dismiss sheet → still on Fleet grid.

## Constraints

- `assertFleetReadOnly` + property tests stay.
- Compose `lib/design/` only; new tile goes in `kelola_components.dart` if needed.
- Saved fleet checks still deferred.
