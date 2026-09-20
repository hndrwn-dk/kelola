#!/usr/bin/env bash
# Build a Play Store release AAB only when private kelola_pro billing is wired.
# Copy the signed AAB into gitignored bundles_release/v<version>/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/check_play_billing.sh"
flutter build appbundle --release "$@"

VERSION="$(awk -F': ' '/^version:/ {gsub(/\r/, "", $2); gsub(/ /, "", $2); print $2; exit}' pubspec.yaml)"
if [[ -z "$VERSION" ]]; then
  echo "build_play_aab: could not read version from pubspec.yaml" >&2
  exit 1
fi

DEST="$ROOT/bundles_release/v${VERSION}"
mkdir -p "$DEST"
cp -f "$ROOT/build/app/outputs/bundle/release/app-release.aab" \
  "$DEST/app-release-${VERSION}.aab"
echo "AAB: $DEST/app-release-${VERSION}.aab"
echo "Play notes: $ROOT/bundles_release/play-console/PLAY_STORE_v${VERSION}.txt"
