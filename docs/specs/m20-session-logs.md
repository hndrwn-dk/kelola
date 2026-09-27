# M20 — Session logs, journal bookmarks, retention

Command sheet output is gone when the sheet closes. Audit stores the
command, not the body. This milestone keeps the output on the phone,
lets the operator pin a journal filter, and expires old logs.

Full design: `docs/superpowers/specs/2026-09-27-m20-session-logs-design.md`.

## Why a new table

`command_history` is unique-per-host reuse without stdout.
Audit is the legal log without a body. Session logs are
`(id, hostId, title, body, createdAt, bookmarked)` — one row per Send.

## Why bookmarks stay on Logs

A journal bookmark is the current filter (unit, query, scope,
priority, 1h). Tap restores it. Deleting a host deletes its rows.

## Retention

Settings: 7 / 14 / 30 / 90 days. Default 14. Bookmarked session logs
never expire. Non-bookmarked also cap at 100 per host.

## Out of scope

Hosted retention. LLM. Light theme. B2. PTY transcript.
