# OpenShift fixtures (M48)

Every file named `synthetic_*` is **synthetic**: hand-written to the shape
of the real API object, not captured from a cluster. Each one also carries a
top-level `"_synthetic"` key saying what it models. Parsers ignore the key.

Synthetic cases (spec §6): pool mid-rollout, degraded node with reason,
paused pool, two pending CSRs, operator `Available=False`, `Failing=True`
ClusterVersion.

## TODO: capture from CRC (OpenShift Local)

Not in the repo yet. With `oc` logged in as `kubeadmin` on the CRC machine,
run `bash scripts/capture_crc_fixtures.sh` there, or
`bash scripts/capture_crc_fixtures.sh user@bastion` from the dev machine. It
runs the read-only commands below, strips the cluster ID, CSR bodies and
`managedFields` when `jq` is installed, and writes the files here.
`test/openshift_crc_fixtures_test.dart` picks each one up automatically (it
skips a file that is missing).

- [ ] `clusterversion.json` — `oc get clusterversion version -o json`
- [ ] `clusteroperators.json` — `oc get clusteroperators -o json`
- [ ] `machineconfigpools.json` — `oc get machineconfigpools -o json`
- [ ] `csr.json` — `oc get csr -o json`
- [ ] `nodes.json` — `oc get nodes -o json`
- [ ] `config_openshift_io_v1.json` — `oc get --raw=/apis/config.openshift.io/v1`
- [ ] `rpm_ostree_status.json` — on the CRC VM as `core@`: `rpm-ostree status --json`
