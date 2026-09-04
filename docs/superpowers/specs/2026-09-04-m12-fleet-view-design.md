# M12 Fleet health grid — design

**Date:** 2026-09-04  
**Status:** approved (chat) — scope A; saved fleet checks deferred

## Goal

One screen: health of every host (reachability, load, disk, failed units, pending updates). Parallel, progressive, severity-sorted. Tags for filter. Read probes only.

## Out of scope

Saved fleet checks (pick probe → run across group). Deferred until real repeat patterns appear.

## Data

- **Tags:** multi-value. Table `host_tags(host_id, tag)` PK `(host_id, tag)`. UI v1: filter by one tag at a time (chips). Host edit/settings can set tags (comma or chips).
- **Fleet cache:** last-known row per host (`fleet_cache`): load1, diskRootPercent, failedUnitCount, pendingUpdates, reachable, fetchedAt. Offline / timeout shows cache with age label (`Host.ageLabel` / 15m stale rule).

## Execution

- `runPooled` concurrency **5**, per-host timeout **10s** (existing `pooled_run.dart`).
- One read SSH round-trip per host: `FleetHealthProbe` (extends dashboard-like shell + package pending count section) → `FleetHostHealth`.
- Progressive: each host completion updates UI list immediately; slow hosts do not block others.
- Sort by severity: unreachable > failed units > disk high > pending updates > load high > healthy; then alias.

## Scope gate

- Fleet mode only accepts `RiskLevel.read`. Property test: every concrete `Probe` with `risk != read` throws when invoked under `ProbeScope.fleet` (same gate as snippets).
- Snippets already reject fleet; keep consistent.
- No mutate/destructive reachable from fleet screen code paths.

## UI

- Compose `lib/design/` only: `RiskBand`, `ServiceRow`, `FilterPill`, `StatCard` as needed. No FAB, no gauges, no plain Card/ListTile.
- Entry from hosts list footer.
- Mono for numbers/ages; display/body for labels.

## Tests

- Property: fleet gate rejects non-read probes.
- Sort/severity pure function.
- Progressive pool: timeout on one item still completes others.
- Schema migration for tags + cache.
- Tag filter multi-value membership.
