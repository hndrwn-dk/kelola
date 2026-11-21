#!/usr/bin/env bash
# Build a Play Store release AAB only when private kelola_pro billing is wired.
# Copy the signed AAB into gitignored bundles_release/v<version>/.
#
# versionCode comes only from pubspec `version: name+N`. Bump +N above the
# highest versionCode Play has ever accepted. See docs/RELEASING.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/check_play_billing.sh"

VERSION="$(awk -F': ' '/^version:/ {gsub(/\r/, "", $2); gsub(/ /, "", $2); print $2; exit}' pubspec.yaml)"
if [[ -z "$VERSION" ]]; then
  echo "build_play_aab: could not read version from pubspec.yaml" >&2
  exit 1
fi
VERSION_NAME="${VERSION%%+*}"
VERSION_CODE="${VERSION##*+}"
if [[ -z "$VERSION_NAME" || -z "$VERSION_CODE" || "$VERSION_NAME" == "$VERSION" ]]; then
  echo "build_play_aab: pubspec version must be name+build (got $VERSION)" >&2
  exit 1
fi

# Keep Settings Version identical to the package metadata in this AAB.
# APP_VERSION turns on the Hosts What's new card (release builds only).
# Do not pass --build-number here: bump pubspec +N instead so the AAB,
# Settings, and lib/app_version.dart stay on one number.
prev=""
for arg in "$@"; do
  case "$arg" in
    --no-obfuscate|--obfuscate|--split-debug-info*)
      echo "build_play_aab: $arg is not allowed; release builds are always obfuscated" >&2
      exit 1
      ;;
    --build-number*|--build-name*|--dart-define=KELOLA_*|--dart-define=APP_VERSION*|--dart-define-from-file*)
      echo "build_play_aab: $arg is not allowed; bump pubspec.yaml version instead" >&2
      exit 1
      ;;
  esac
  # Space form: `--dart-define KELOLA_BUILD=...` arrives as two arguments.
  if [[ "$prev" == "--dart-define" && ( "$arg" == KELOLA_* || "$arg" == APP_VERSION* ) ]]; then
    echo "build_play_aab: --dart-define $arg is not allowed; bump pubspec.yaml version instead" >&2
    exit 1
  fi
  prev="$arg"
done
# Obfuscate Dart symbols so a decompiled AAB does not name the entitlement
# code. Keep the symbol files next to the AAB (gitignored) to decode crash
# stack traces: flutter symbolize -i <trace> -d <symbols>/app.android-arm64.symbols
SYMBOLS="$ROOT/bundles_release/v${VERSION}/symbols"
mkdir -p "$SYMBOLS"
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info="$SYMBOLS" \
  --build-name="$VERSION_NAME" \
  --build-number="$VERSION_CODE" \
  --dart-define=KELOLA_VERSION="$VERSION_NAME" \
  --dart-define=KELOLA_BUILD="$VERSION_CODE" \
  --dart-define=APP_VERSION="$VERSION_NAME" \
  "$@"

DEST="$ROOT/bundles_release/v${VERSION}"
mkdir -p "$DEST"
cp -f "$ROOT/build/app/outputs/bundle/release/app-release.aab" \
  "$DEST/app-release-${VERSION}.aab"
# Release notes travel with the AAB: paste this file into Play Console.
cp -f "$ROOT/docs/store/whatsnew/whatsnew-en-US" "$DEST/whatsnew-en-US.txt"
echo "AAB: $DEST/app-release-${VERSION}.aab"
echo "Symbols: $SYMBOLS (keep them; needed to read crash traces)"
echo "Release notes: $DEST/whatsnew-en-US.txt (paste into Play Console)"
