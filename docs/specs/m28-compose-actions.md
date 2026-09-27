# M28 — Compose project actions

`groupContainersByCompose` already groups by project label. This
milestone adds up / down / restart / pull at project scope.

Full design: `docs/superpowers/specs/2026-09-27-m28-compose-actions-design.md`.

## Why the working directory label

Compose needs `--project-directory`. Guessing a path is how you take
down the wrong stack. If `com.docker.compose.project.working_dir` (or
the podman equivalent) is missing, refuse and say so.

## Risk

Pull / restart / up: mutate. Down: destructive, token = project name.
A stack that fronts SSH uses the existing lockout warning.

## Out of scope

M20 session logs. M27 apply. Fleet. Light theme.
