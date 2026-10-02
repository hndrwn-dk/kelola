# Play Console — release notes (0.2.8)

**Version name:** 0.2.8  
**Version code:** 11  
**Track:** Alpha (or Internal)  
**AAB:** `bundles_release/v0.2.8+11/app-release-0.2.8+11.aab` (gitignored; local only)

**Play paste:** `bundles_release/play-console/PLAY_STORE_v0.2.8+11.txt`

## Short description (Play “Release notes”, en-US)

Vault import no longer wipes local snippet templates or env values when a secrets-off blob wins last-write-wins. Host identity updates no longer get dropped when a TOFU pin shares the host id.

## Longer notes (optional / changelog)

What’s new in 0.2.8 (since 0.2.7+10):

- **Vault snippets / env** — Default (secrets-off) import keeps the local snippet body and env value when those keys are absent from the incoming payload. Metadata such as name still moves forward.
- **Vault hosts** — Diff keys by `kind:id`, so a host-key pin no longer shadows the host row and drop a legitimate alias or identity update from another device.

Unchanged from 0.2.7: full-screen PTY, jump hosts, vault export, Kubernetes YAML apply, Rocky package/SFTP honesty, AppSec fail-closed, HTTPS for OpenAI-compatible Assist.

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
