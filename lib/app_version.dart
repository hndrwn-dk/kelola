/// Marketing/version line from pubspec `version:` (before `+build`).
///
/// Defaults stay in lockstep with pubspec.yaml. Release AAB builds must pass
/// matching `--dart-define=KELOLA_VERSION=` / `KELOLA_BUILD=` alongside
/// `--build-name` / `--build-number` so Settings shows the same values as the
/// installed package. Do not add package_info_plus for this.
const kelolaAppVersion = String.fromEnvironment(
  'KELOLA_VERSION',
  defaultValue: '0.5.0',
);

/// Build number (Play versionCode) from pubspec `version:` after `+`.
/// `scripts/build_play_aab.sh` injects the same value via `KELOLA_BUILD`.
const kelolaVersionCode = String.fromEnvironment(
  'KELOLA_BUILD',
  defaultValue: '120',
);

/// Flutter SDK line from README. Keep in lockstep; not read from the device.
const kelolaFlutterVersion = '3.47';

/// versionName of a release build, for the What's new card only.
///
/// Empty unless the build passes `--dart-define=APP_VERSION=<versionName>`
/// (`scripts/build_play_aab.sh` does). Debug builds, `flutter run` and tests
/// leave it empty, so the card never shows there unless a test overrides
/// `appVersionProvider`. Deliberately no default: unlike [kelolaAppVersion]
/// this must not fall back to the pubspec value.
const kelolaReleaseVersion = String.fromEnvironment('APP_VERSION');
