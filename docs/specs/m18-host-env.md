# M18 — Environment variables and tag inheritance

Free. Host tags are the group. Tag env applies to every host with
that tag. Host env overrides. Used only on Command sheet and snippet
runs — never fleet probes.

Full design: `docs/superpowers/specs/2026-09-27-m18-host-env-design.md`.

## Rules

- Names must be `^[A-Za-z_][A-Za-z0-9_]*$`. Values are
  POSIX-quoted. Invalid names never reach the host.
- Resolve order: tags alphabetically, then host. Last write wins.
- Inject inside the existing `/bin/sh -c` for `CommandRunnerProbe`
  and `SnippetProbe` only.
- Settings lists tag env. Edit host lists host overrides plus
  inherited rows.
- Vault packs env records. StrongBox still never syncs.
