# Play Console — release notes (0.2.10)

**Version name:** 0.2.10  
**Version code:** 13  
**Track:** Alpha (or Internal)  
**AAB:** `bundles_release/v0.2.10+13/app-release-0.2.10+13.aab` (gitignored; local only)

**Play paste:** `bundles_release/play-console/PLAY_STORE_v0.2.10+13.txt`

## Short description (Play “Release notes”, en-US)

Assist API keys are masked in Settings: saved keys show only a hint (last four characters), never the full secret, with Replace and Remove instead of a pre-filled field.

## Longer notes (optional / changelog)

What’s new in 0.2.10 (since 0.2.9+12):

- **API key masking** — OpenAI-compatible Assist keys are never pre-filled into the settings field. A saved key shows a masked hint only; Replace opens an empty obscured input, and Remove clears the key from secure storage.
- **Hint storage** — Last-four hint is kept next to the key in secure storage (not Drift); legacy keys get a hint on first read without exposing the secret to the UI.

Also on this track from 0.2.9: Help & FAQ, Privacy, Terms, Play review, and Share Kelola from Settings.

## Play App content — FGS

If not already submitted for this package: paste from `docs/play/fgs-declaration.md` (specialUse justification, impact if deferred/interrupted, demo shot list).

## Build

```bash
# Requires pubspec_overrides.yaml pointing kelola_pro at the private billing
# package. The check refuses a std-stub AAB (all Pro unlocked).
bash scripts/build_play_aab.sh
```

Signed with `android/key.properties` → upload keystore.

Do **not** run bare `flutter build appbundle --release` for Play — that skips the billing gate.
