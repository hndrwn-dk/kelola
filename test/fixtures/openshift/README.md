# OpenShift fixtures (M48)

Every file named `synthetic_*` is **synthetic**: hand-written to the shape
of the real API object, not captured from a cluster. Each one also carries a
top-level `"_synthetic"` key saying what it models. Parsers ignore the key.

Synthetic cases (spec §6): pool mid-rollout, degraded node with reason,
paused pool, two pending CSRs, operator `Available=False`, `Failing=True`
ClusterVersion.

## TODO: capture from CRC (OpenShift Local)

Not in the repo yet. Capture on the CRC bastion with `oc` logged in as
`kubeadmin`, redact the cluster ID / certificates if you like, and drop the
files here under exactly these names. `test/openshift_crc_fixtures_test.dart`
picks each one up automatically (it skips a file that is missing).

- [ ] `clusterversion.json` — `oc get clusterversion version -o json`
- [ ] `clusteroperators.json` — `oc get clusteroperators -o json`
- [ ] `machineconfigpools.json` — `oc get machineconfigpools -o json`
- [ ] `csr.json` — `oc get csr -o json`
- [ ] `nodes.json` — `oc get nodes -o json`
- [ ] `config_openshift_io_v1.json` — `oc get --raw=/apis/config.openshift.io/v1`
- [ ] `rpm_ostree_status.json` — on the CRC VM as `core@`: `rpm-ostree status --json`
