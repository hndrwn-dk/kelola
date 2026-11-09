#!/usr/bin/env bash
# Capture the seven M48 CRC fixtures (docs/specs/m48-openshift.md §6) into
# test/fixtures/openshift/. Read-only: only `oc get` and `rpm-ostree status`.
#
#   bash scripts/capture_crc_fixtures.sh                # on the CRC machine
#   bash scripts/capture_crc_fixtures.sh user@bastion   # from the dev machine
#
# Needs `oc` logged in on the CRC machine (`oc login -u kubeadmin …`).
# With `jq` installed here, the cluster ID, CSR bodies and managedFields are
# stripped before the files are written. Review the diff before committing.
set -uo pipefail

BASTION="${1:-}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/test/fixtures/openshift"

# Same resolution the app uses (KubectlFlavor.oc): PATH first, then CRC's copy.
OC='OC=$(command -v oc || echo "$HOME/.crc/bin/oc/oc"); "$OC"'

# rpm-ostree runs on the CRC VM as core@, reached from the CRC machine.
# User-mode networking (macOS, Windows) forwards the VM's sshd to 127.0.0.1:2222.
OSTREE='ip=$(crc ip) || exit 1
key=$(ls "$HOME"/.crc/machines/crc/id_ed25519 "$HOME"/.crc/machines/crc/id_ecdsa 2>/dev/null | head -1)
port=22; [ "$ip" = 127.0.0.1 ] && port=2222
ssh -i "$key" -p "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "core@$ip" rpm-ostree status --json'

run() {
  if [ -n "$BASTION" ]; then ssh "$BASTION" "$1"; else bash -c "$1"; fi
}

redact() {
  command -v jq >/dev/null 2>&1 || { cat; return; }
  jq 'del(.. | objects | .managedFields)
      | (.. | objects | select(has("clusterID")) | .clusterID) = "00000000-0000-0000-0000-000000000000"
      | (.. | objects | select(has("request") and (.request | type == "string")) | .request) = "REDACTED"
      | (.. | objects | select(has("certificate") and (.certificate | type == "string")) | .certificate) = "REDACTED"'
}

failed=0
capture() {
  local name="$1" cmd="$2" tmp
  tmp="$(mktemp)"
  if run "$cmd" </dev/null >"$tmp" 2>"$tmp.err" && [ "$(head -c1 "$tmp")" = "{" ] \
      && redact <"$tmp" >"$OUT/$name"; then
    echo "ok    $name"
  else
    rm -f "$OUT/$name"
    echo "FAIL  $name: $(tail -1 "$tmp.err" 2>/dev/null)"
    failed=1
  fi
  rm -f "$tmp" "$tmp.err"
}

capture clusterversion.json         "$OC get clusterversion version -o json"
capture clusteroperators.json       "$OC get clusteroperators -o json"
capture machineconfigpools.json     "$OC get machineconfigpools -o json"
capture csr.json                    "$OC get csr -o json"
capture nodes.json                  "$OC get nodes -o json"
capture config_openshift_io_v1.json "$OC get --raw=/apis/config.openshift.io/v1"
capture rpm_ostree_status.json      "$OSTREE"

command -v jq >/dev/null 2>&1 || echo "note: jq not found here, files written unredacted"
echo "then: flutter test test/openshift_crc_fixtures_test.dart"
exit "$failed"
