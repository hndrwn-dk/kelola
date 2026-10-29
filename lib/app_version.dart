/// Marketing/version line from pubspec `version:` (before `+build`).
///
/// Defaults stay in lockstep with pubspec.yaml. Release AAB builds must pass
/// matching `--dart-define=KELOLA_VERSION=` / `KELOLA_BUILD=` alongside
/// `--build-name` / `--build-number` so Settings shows the same values as the
/// installed package. Do not add package_info_plus for this.
const kelolaAppVersion = String.fromEnvironment(
  'KELOLA_VERSION',
  defaultValue: '0.3.5',
);

/// Build number from pubspec `version:` after `+`, or the CI Play versionCode
/// when injected via `KELOLA_BUILD`.
const kelolaVersionCode = String.fromEnvironment(
  'KELOLA_BUILD',
  defaultValue: '21',
);

/// Flutter SDK line from README. Keep in lockstep; not read from the device.
const kelolaFlutterVersion = '3.47';
