# Play Console — release notes (0.2.9)

**Version name:** 0.2.9  
**Version code:** 12  
**Track:** Alpha (or Internal)  
**AAB:** `bundles_release/v0.2.9+12/app-release-0.2.9+12.aab` (gitignored; local only)

**Play paste:** `bundles_release/play-console/PLAY_STORE_v0.2.9+12.txt`

## Short description (Play “Release notes”, en-US)

Settings now includes Help & FAQ, Privacy, Terms of Service, Play Store reviews, and Share Kelola so testers can get support and leave feedback from the app.

## Longer notes (optional / changelog)

What’s new in 0.2.9 (since 0.2.8+11):

- **Help & FAQ** — In-app answers for adding a host, where keys live, vault export, app lock, and how to report a problem.
- **Legal** — Privacy and Terms of Service open from Settings (`tursinalabs.com/kelola`).
- **Feedback** — Rate & review opens the Play listing so testers can use the store review field.
- **Share** — Share Kelola sends the Play listing URL through the system share sheet.

Also on this track from 0.2.8: vault import keeps local snippet templates and env values on a secrets-off blob; host identity updates are no longer shadowed by a TOFU pin.

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
