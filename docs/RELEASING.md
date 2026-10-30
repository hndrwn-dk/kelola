# Releasing Kelola (Play)

## What counts as a release

A **release** is a push to `main` that changes **versionName** in
`pubspec.yaml` (the part before `+`). Patch for fixes, minor for
features. CI ignores the `+N` build metadata for release detection.

Together with the versionName bump you **must**:

1. Update `lib/app_version.dart` default values to the same name and
   `+N` (Settings reads these; AAB builds also inject matching
   `--dart-define=KELOLA_VERSION` / `KELOLA_BUILD`).
2. Replace `docs/store/whatsnew/whatsnew-en-US` with notes for **this
   version only** (plain text, ≤ 500 characters, no language tags).
   Never paste older releases' notes into that file.

`test/app_version_lockstep_test.dart` fails CI if defaults drift from
pubspec or if the AAB build drops the dart-defines.

Other changes (docs, tests, CI, refactors) must not bump versionName
and must not rewrite whatsnew.

Longer optional changelog stays in `docs/play/release-notes-*.md`.
Play Console only receives `docs/store/whatsnew/`.

## versionCode (CI offset)

CI sets:

```text
versionCode = github.run_number + 100
```

`OFFSET=100` exists because no Actions workflow had run while Play
already had versionCode **18** (0.3.2). The first CI release therefore
starts at **101** (or higher once run_number grows), never colliding
with live codes ≤ 18.

## Tracks

Push to `main` (including versionName bumps) always resolves
`track=none` — CI does **not** auto-build or upload to Play. Version
bumps still require `docs/store/whatsnew/whatsnew-en-US` and a
strictly greater versionName.

Play releases are **manual**:

1. Build a private-billing AAB locally (`bash scripts/build_play_aab.sh`,
   with `pubspec_overrides` → private `kelola-pro`) **or** run
   `workflow_dispatch` on `main` with `play_track` set.
2. Install on the Pixel 8 Pro (Internal testing) and verify against lab
   SSH hosts / StrongBox.
3. **Promote** the same artifact to production in Play Console (no
   rebuild) when ready.

`workflow_dispatch` (main only) can target `internal` / `alpha` /
`beta` / `production` (or `none`). Production uploads use
`status: draft`; other tracks use `completed`.

## Private billing gate

Play AABs must **not** ship the in-repo `packages/kelola_pro` stub
(OpenEntitlement / label `std` / all Pro unlocked).

Release builds:

1. Check out `hndrwn-dk/kelola-pro` into `.gate_tmp_kelola_pro/` with
   deploy key `KELOLA_PRO_DEPLOY_KEY`.
2. Write gitignored `pubspec_overrides.yaml` pointing `kelola_pro` at
   that path.
3. Run `dart run scripts/check_play_billing.dart` — failure stops the
   job.

Never commit `pubspec_overrides.yaml`, keystores, or
`.gate_tmp_kelola_pro/`. Never print overrides or private package
contents in public Actions logs.

Analyze/test on PRs and non-release pushes use the stub (no secret).

## Secrets (`play` environment, main only)

| Secret | Purpose |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | Upload keystore (base64) |
| `ANDROID_KEYSTORE_PASSWORD` | Store password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play Developer API service account |
| `KELOLA_PRO_DEPLOY_KEY` | Read-only deploy key for `kelola-pro` |

## Manual fallback

`bash scripts/build_play_aab.sh` remains the local path (requires
`pubspec_overrides.yaml` + billing gate + `android/key.properties`).

For a manual Play upload, pass a `--build-number` **higher** than the
last CI versionCode (`run_number + 100`), or Play rejects the AAB.

Example:

```bash
bash scripts/build_play_aab.sh --build-number=200
```

(`build_play_aab.sh` forwards args to `flutter build appbundle`.)

## Reading CI

Job **Analyze & test** always runs. Annotations (`::error` /
`::warning`) point at analyzer findings and failed tests.
`flutter analyze` uses `--no-fatal-infos --no-fatal-warnings` so
existing infos/warnings do not fail the job; only analyzer **errors**
fail CI.

Jobs **Build Play AAB** and **Upload to Google Play** run only when
`track != none`, under the `play` environment.

## Device verification

No emulator or `integration_test` in CI. Real SSH hosts and StrongBox
are verified on device via the Internal testing track.
