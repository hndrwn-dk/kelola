#!/usr/bin/env bash
# Build a Play Store release AAB only when private kelola_pro billing is wired.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/check_play_billing.sh"
exec flutter build appbundle --release "$@"
