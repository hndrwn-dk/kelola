# M21 — Snippet multi-execution

Pro unlock convenience: run one snippet on many hosts the snippet
already applies to. Never fleet, never auto-run.

Full design: `docs/superpowers/specs/2026-09-27-m21-snippet-multi-design.md`.

## Rules

- Own executor. Each host goes through `runSnippet` with
  `ProbeScope.host`. `ProbeScope.fleet` stays forbidden.
- Dry-run preview shows the resolved command per host before any
  execute. `{{host}}` is that host's alias. Other bindings are shared.
- Destructive and mutate confirm per host. Destructive token is the
  host alias, same as the single-host run sheet.
- Only hosts `snippetAppliesToHost` accepts. Do not invent extras.
- Entitlement `ProFeature.snippetMulti` lives in the run sheet, never
  in `lib/domain/snippets`.
- Sequential. A skip or failure on one host does not abort the rest.
