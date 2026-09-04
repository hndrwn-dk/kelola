# M7 LLM Assist Implementation Plan

> **For agentic workers:** Use TDD. Architecture graph test fails first.

**Goal:** Ship M7 LLM assist with structural isolation from SSH execute.

**Architecture:** Domain LLM module + data HTTP clients; UI only at the edges; always redact; catalog+context for intent.

**Tech Stack:** Flutter/Dart, Drift settings, dart:io HttpClient, existing redact.dart and Probe types.

## Global Constraints

- Compose from `lib/design/` only.
- Redact all providers including Ollama.
- No `execute` / `session_pool` reachable from `lib/domain/llm` or `lib/data/llm`.
- Provider default `none`.
- Intent → catalog Probe + context params only.

---

### Task 1: Architecture + client isolation tests (RED)

- [ ] `test/llm_architecture_test.dart` — transitive import graph
- [ ] `test/llm_http_egress_test.dart` — fake throws on foreign host
- [ ] `test/llm_redact_payload_test.dart` — client sees redacted body
- [ ] `test/llm_catalog_test.dart` — context param validation
- [ ] `test/llm_settings_test.dart` — default none

### Task 2: Domain + data LLM (GREEN)

- [ ] Settings, catalog, context, propose, session, assist service
- [ ] Http client + ollama + openai-compatible
- [ ] Drift schema 8 columns

### Task 3: UI wire

- [ ] Settings provider row
- [ ] Incident Explain, Journal Summarise, Command intent
- [ ] Cloud preview sheet once per session

### Task 4: Verify

- [ ] `flutter test` on llm_* + related
- [ ] Update `readiness/PROGRESS.md`
