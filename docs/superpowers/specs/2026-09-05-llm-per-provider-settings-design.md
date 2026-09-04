# Per-provider LLM settings — design

**Date:** 2026-09-05  
**Status:** approved (chat)

## Goal

Persist Ollama and OpenAI-compatible endpoint configs independently. Switching providers must not overwrite or bleed fields. Incomplete configs must not become the active Assist provider. Hosts footer must reflect the saved active provider.

## Schema (v11)

Keep `llm_provider` as the **active** provider. Add columns (do not drop legacy shared fields):

| Column | Purpose |
|---|---|
| `llm_ollama_base_url` | Ollama base URL |
| `llm_ollama_model` | Ollama model |
| `llm_openai_base_url` | OpenAI-compatible base URL |
| `llm_openai_api_key` | OpenAI-compatible API key |
| `llm_openai_model` | OpenAI-compatible model |

Legacy `llm_base_url` / `llm_api_key` / `llm_model` remain in the table but are no longer written. Migration `from < 11` adds columns and copies legacy values into the matching provider slot based on current `llm_provider`.

## Domain

- `LlmEndpointConfig` — baseUrl / apiKey / model + `isCompleteFor(provider)`
- `LlmSettingsBundle` — activeProvider + ollama + openaiCompatible configs
- `LlmSettings` — resolved **active** view for Assist HTTP (unchanged callers)

OpenAI-compatible still requires user base URL + model + API key. Placeholder hint only: `https://api.openai.com/v1`. No baked default URL.

## Save / activate rules

1. Always persist the edited provider’s fields into that provider’s slot.
2. Set `activeProvider` to the draft only if draft is `none` **or** that provider’s config is complete.
3. If draft is incomplete: keep previous active; show clear “not configured” affordance on that row.
4. Selecting a chip loads that provider’s stored fields (empty if never saved).

## Hosts footer

Replace hardcoded `LLM · default none` with live `llmSettingsProvider` meta:

- none → `LLM · none`
- active + configured → `LLM · ollama` / `LLM · openai`
- active but incomplete (should be rare) → `LLM · not configured`
