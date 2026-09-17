#!/usr/bin/env bash
# Refuse a Play release AAB unless kelola_pro resolves to the private billing
# package (not the in-repo OpenEntitlement stub that labels builds "std").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec dart run "$ROOT/scripts/check_play_billing.dart"
