# Hosts / Fleet split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or implement task-by-task with TDD.

**Goal:** Hosts = inventory; Fleet = progressive dense monitor tiles with richer batched health + tap sheet.

**Architecture:** Expand `FleetHostHealth` + `FleetHealthProbe` (no CPU sample sleep); `FleetHostTile` in design system; Fleet grid progressive; tap opens fleet-aware incident sheet with ≤2 ranked actions + Open host.

**Tech Stack:** Flutter, existing probes/session pool, Drift schema 10 for fleet_cache columns.

## Global Constraints

- Compose from `lib/design/` only.
- No dual `/proc/stat` on fleet tile refresh.
- Progressive tile updates per host done.
- `assertFleetReadOnly` preserved.
- Pill kept on Hosts; metric detail removed.

---

### Task 1: Domain model + probe (TDD)

- [ ] Expand health model; severity includes containers/security/mem/reboot
- [ ] Probe: one batch; parse mounts>85%, containers, security, reboot; no sleep/stat2
- [ ] `fleetQuickActions` priority + `+N more`

### Task 2: Cache schema 10

- [ ] Extra fleet_cache columns; migration test

### Task 3: Hosts inventory UI

- [ ] Remove detail metrics; keep pill

### Task 4: Fleet tile grid + sheet

- [ ] `FleetHostTile` in kelola_components
- [ ] Grid progressive; tap → sheet (CPU/top on demand, actions, Open host)

### Task 5: Verify + PROGRESS

- [ ] Tests green; update PROGRESS.md
