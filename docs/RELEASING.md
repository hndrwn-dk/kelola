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
   version only** (plain text, ≤ 500 characters, no language tags, one
   `- ` line per point, at most three points). Never paste older
   releases' notes into that file.
3. Replace `WhatsNewStrings.notes` in
   `lib/presentation/whats_new_strings.dart` with the same lines minus
   the leading `- `. The Hosts screen shows them once in the What's new
   card after the update. `test/whats_new_test.dart` fails if the file and
   the list differ.

`test/app_version_lockstep_test.dart` fails CI if defaults drift from
pubspec or if the AAB build drops the dart-defines.

Other changes (docs, tests, CI, refactors) must not bump versionName
and must not rewrite whatsnew or `WhatsNewStrings.notes`.

Play Console only receives `docs/store/whatsnew/`.

## What's new card

The card only appears in builds that pass
`--dart-define=APP_VERSION=<versionName>` (`scripts/build_play_aab.sh`
does, and refuses overrides). Debug builds, `flutter run` and tests leave
it empty, so the card stays hidden there. It shows when the device key
exists (setup finished) and `AppSettings.seenVersion` differs from
`APP_VERSION`; closing it stores the version. A fresh install stores its
version when the first device key is created, so it never sees the card.

## versionCode

`versionCode` is **only** the `+N` in `pubspec.yaml` `version: name+N`.
`scripts/build_play_aab.sh` passes it as `--build-number` and as
`--dart-define=KELOLA_BUILD`, so the AAB package metadata, Play Console,
and Settings → Version all show the same number. The script refuses
`--build-number` / `--build-name` overrides.

On every versionName bump, raise `+N` above the highest versionCode Play
has ever accepted (any track). The old CI uploads used
`run_number + 100`, which is why 0.3.6 jumped to `+117`. CI fails a
release bump whose `+N` does not increase.

## Building and uploading (manual)

CI does **not** build or upload AABs (the Play jobs were removed: there
is no device/test server in Actions, and a second versionCode formula
in CI drifted from pubspec).

1. Wire the private billing package (see below) and
   `android/key.properties` locally.
2. `bash scripts/build_play_aab.sh` → `bundles_release/v<version>/`.
3. Upload the AAB in Play Console → Internal testing. Paste
   `docs/store/whatsnew/whatsnew-en-US` as release notes. The R8 mapping
   ships inside the AAB (`BUNDLE-METADATA/.../obfuscation/proguard.map`), so
   no separate upload is needed. To check, open the bundle under Test and
   release → Latest releases and bundles → Downloads → Assets. If ReTrace
   mapping file is empty, upload
   `build/app/outputs/mapping/release/mapping.txt` there.
4. Install on the Pixel 8 Pro and verify against lab SSH hosts /
   StrongBox. Settings → Version must read `name (+N)` from pubspec.
5. **Promote** the same artifact to production in Play Console (no
   rebuild) when ready.

## Private billing gate

Play AABs must **not** ship the in-repo `packages/kelola_pro` stub
(OpenEntitlement / label `std` / all Pro unlocked).

Local release builds:

1. Check out `hndrwn-dk/kelola-pro` into `.gate_tmp_kelola_pro/`.
2. Write gitignored `pubspec_overrides.yaml` pointing `kelola_pro` at
   that path.
3. `scripts/build_play_aab.sh` runs the billing gate first — failure
   stops the build.

Never commit `pubspec_overrides.yaml`, keystores, or
`.gate_tmp_kelola_pro/`.

Analyze/test in CI always use the stub (no secrets).

The repo is public: no workflow uses secrets or GitHub environments, and
none should be added. Signing and Play upload stay on the maintainer's
machine.

## Reading CI

Job **Analyze & test** always runs. Annotations (`::error` /
`::warning`) point at analyzer findings and failed tests.
`flutter analyze` uses `--no-fatal-infos --no-fatal-warnings` so
existing infos/warnings do not fail the job; only analyzer **errors**
fail CI.

Step **Release metadata gate** fails a versionName bump that lacks
fresh whatsnew notes, a greater versionName, or a greater `+N`.

## Device verification

No emulator or `integration_test` in CI. Real SSH hosts and StrongBox
are verified on device via the Internal testing track.
