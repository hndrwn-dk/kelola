# M7 LLM assist — design

**Date:** 2026-09-04  
**Status:** approved (chat)

## Goal

Optional LLM assist for explain / summarise / intent→probe. Default provider None. No Tursina endpoint, no proxy, no bundled key.

## Surfaces

- Incident sheet: Explain (failed unit / disk context already loaded)
- Journal: Summarise selection
- Command sheet: intent → catalog Probe proposal only (never free-form shell)

## Boundaries

- `lib/domain/llm/**` and `lib/data/llm/**` must have no transitive import path to `session_pool.dart`, `host_session.dart`, or `runHostProbe`.
- Architecture test walks the Dart import graph recursively; string scan is supplemental.
- Presentation wires Assist → user confirm → existing `runHostProbe` / Command field. LLM code never executes.

## Providers

| Provider | Config | Preview |
|---|---|---|
| none | default | n/a |
| ollama | user base URL (+ model) | no per-session approve; still redacted |
| openaiCompatible | user base URL + API key (+ model) | exact payload preview once per session before first request |

## Redaction

Always redact with `lib/domain/redaction/redact.dart` before any provider request, including Ollama. Tests assert the body received by the HTTP client is redacted.

## Catalog + context

Model returns `probeKind` + parameters. Parameters must be members of the loaded `AssistContext` (e.g. unit names currently in scope). Proposals outside catalog or outside context are rejected as "tidak ada aksi tersedia". Risk comes from the Probe type, not string guessing.

## HTTP

Injected client. Production hits only the configured base URL. Test fake throws on any other authority.
