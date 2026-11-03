/// Marketing/version line from pubspec `version:` (before `+build`).
///
/// Defaults stay in lockstep with pubspec.yaml. Release AAB builds must pass
/// matching `--dart-define=KELOLA_VERSION=` / `KELOLA_BUILD=` alongside
/// `--build-name` / `--build-number` so Settings shows the same values as the
/// installed package. Do not add package_info_plus for this.
const kelolaAppVersion = String.fromEnvironment(
  'KELOLA_VERSION',
  defaultValue: '0.3.6',
);

/// Build number (Play versionCode) from pubspec `version:` after `+`.
/// `scripts/build_play_aab.sh` injects the same value via `KELOLA_BUILD`.
const kelolaVersionCode = String.fromEnvironment(
  'KELOLA_BUILD',
  defaultValue: '117',
);

/// Flutter SDK line from README. Keep in lockstep; not read from the device.
const kelolaFlutterVersion = '3.47';
