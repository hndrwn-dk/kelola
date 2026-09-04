# Per-provider LLM settings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist Ollama and OpenAI-compatible Assist configs separately, gate incomplete activation, and fix the Hosts Assist footer.

**Architecture:** Schema 11 adds per-provider columns on `app_settings`. Domain exposes `LlmSettingsBundle`; Assist keeps consuming resolved `LlmSettings`. Settings UI swaps field controllers from the selected provider’s stored slot.

**Tech Stack:** Flutter, Drift, Riverpod, existing Kelola design components.

## Global Constraints

- Dark theme only; compose from `kelola_components` / `kelola_theme`.
- No hardcoded `api.openai.com` as a default value — hint/placeholder only.
- Schema migration stepwise `from < n` (here `from < 11`).
- No Tursina endpoint; user owns the URL.

---

### Task 1: Domain model + unit tests

**Files:**
- Create: `lib/domain/llm/endpoint_config.dart` (or extend `settings.dart`)
- Modify: `lib/domain/llm/settings.dart`
- Create/Modify: `test/llm_settings_test.dart`

- [ ] Write failing tests: separate ollama/openai configs; incomplete openai cannot resolve as configured; bundle resolves active fields.
- [ ] Implement `LlmEndpointConfig`, `LlmSettingsBundle`, keep `LlmSettings.isConfigured`.
- [ ] Pass tests.

### Task 2: Schema 11 + Drift codegen

**Files:**
- Modify: `lib/data/db/tables.dart`, `lib/data/db/database.dart`
- Regenerate: `lib/data/db/database.g.dart`

- [ ] Add six nullable text columns (ollama×2, openai×3).
- [ ] `schemaVersion => 11`; `if (from < 11)` add columns + SQL copy from legacy.
- [ ] `dart run build_runner build --delete-conflicting-outputs`

### Task 3: Repository

**Files:**
- Modify: `lib/data/db/host_repository.dart`
- Modify: `test/llm_settings_test.dart`

- [ ] Failing test: save ollama, save openai, reload — both intact; active switches.
- [ ] `loadLlmSettingsBundle` / `saveLlmSettingsBundle`; `loadLlmSettings` returns resolved active.
- [ ] Update every `AppSettingsCompanion` write to preserve new columns.
- [ ] Pass tests.

### Task 4: Settings UI + Hosts footer

**Files:**
- Modify: `lib/presentation/screens/llm_settings_screen.dart`
- Modify: `lib/presentation/screens/hosts_screen.dart`
- Modify: `lib/presentation/assist_flow.dart` (clearer error if incomplete)

- [ ] Load bundle; switch provider swaps controllers from that slot.
- [ ] Pill `selected` vs `not configured`; Save persists slot + activates only if complete/none.
- [ ] Hosts Assist meta from `llmSettingsProvider`.
- [ ] OpenAI Base URL hint `https://api.openai.com/v1` only.

### Task 5: Verify

- [ ] `flutter test test/llm_settings_test.dart`
- [ ] `dart analyze` on touched files
