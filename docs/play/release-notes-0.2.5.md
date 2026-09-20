# Play Console — release notes (0.2.5)

**Version name:** 0.2.5  
**Version code:** 8  
**Track:** Alpha (or Internal)  
**AAB:** `bundles_release/v0.2.5+8/app-release-0.2.5+8.aab` (gitignored; local only)

**Play paste:** `bundles_release/play-console/PLAY_STORE_v0.2.5+8.txt`

## Short description (Play “Release notes”, en-US)

Hosts list no longer sits under the status bar. Each host shows load, memory, and disk on a third line from the last fleet check. The Audit sheet can be closed and stays below the clock.

## Longer notes (optional / changelog)

What’s new in 0.2.5:

- **Status bar** — Shared wash chrome uses one SafeArea so the Kelola wordmark, titles, and app-bar icons sit below the clock, Wi-Fi, and battery. Hosts no longer grows a second empty gap under the header.
- **Host metrics** — Inventory rows show `load … · mem …% · disk …%` under the IP/OS line from the fleet cache. Unknown values are omitted; the right side is status badge and chevron only.
- **Audit sheet** — Long command details stay scrollable, with a drag handle and Close, and the title clears the status bar.
- Hosts utility rail (Fleet / AI Assist / Widget), Rocky fleet-probe timeouts, dashboard card denominators, and first-run Alpha polish from the 0.2.4 track.

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
