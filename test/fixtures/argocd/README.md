# Argo CD fixtures (M49)

Every fixture here is synthetic: hand-written to match what the read returns,
not captured from a cluster. A replacement is captured on the spec section 7
lab (Argo CD installed in `argocd`, the `guestbook` example, plus the extra
apps the table names) with the command in the last column. The OpenShift GitOps
fixture stays synthetic: CRC checks are waived by the owner.

JSON files are the `kubectl ... -o json` body; tests wrap them in
`---APPS---` the way `ArgoAppsProbe` prints. Text files are whole probe
sections. Every JSON fixture carries `"_synthetic": true`.

| File | Origin | Covers | Lab command to capture a replacement |
| --- | --- | --- | --- |
| `apps_guestbook_synced.json` | synthetic | A healthy, synced, single-source app set | `kubectl get applications.argoproj.io -A -o json > apps_guestbook_synced.json` |
| `apps_outofsync_manual.json` | synthetic | Out of sync app with a manual sync policy | `kubectl get applications.argoproj.io -A -o json > apps_outofsync_manual.json` after changing the guestbook repo revision |
| `apps_degraded.json` | synthetic | Degraded and missing health | `kubectl get applications.argoproj.io -A -o json > apps_degraded.json` after breaking an image tag |
| `apps_sync_failed.json` | synthetic | Last operation failed, with a message | `kubectl get applications.argoproj.io -A -o json > apps_sync_failed.json` after syncing an invalid manifest |
| `apps_multisource.json` | synthetic | `spec.sources` and `status.sync.revisions` | `kubectl get applications.argoproj.io -A -o json > apps_multisource.json` after creating a multi-source app |
| `apps_helm_secrets.json` | synthetic | Helm values, plugin env, kustomize patches and jsonnet that must never be read | `kubectl get applications.argoproj.io -A -o json > apps_helm_secrets.json` with throwaway fake secrets in those fields |
| `apps_token_url.json` | synthetic | Repo URLs with credentials, query and fragment | `kubectl get applications.argoproj.io -A -o json > apps_token_url.json` with a repo URL carrying a fake token |
| `apps_300_resources.json` | synthetic | A large resource list (status.resources) | `kubectl get applications.argoproj.io -A -o json > apps_300_resources.json` for an app with hundreds of resources |
| `apps_openshift_gitops.json` | synthetic | Applications in `openshift-gitops` (OpenShift GitOps) | `oc get applications.argoproj.io -A -o json > apps_openshift_gitops.json` on a cluster with the GitOps operator |
| `apps_forbidden.txt` | synthetic | `---APPS_ERR---` with a Forbidden reason | `kubectl --as=system:serviceaccount:kelola:kelola-reader get applications.argoproj.io -A -o json 2>&1 \| tail -4` |
| `apps_junk.txt` | synthetic | Truncated JSON and stray lines, no error section | no capture: hand-made corruption of `apps_guestbook_synced.json` |
| `crd_present.txt` | synthetic | `---ARGO_CRD---` read succeeded | `kubectl get crd applications.argoproj.io -o name` |
| `crd_absent.txt` | synthetic | CRD NotFound (no Argo CD) | `kubectl get crd applications.argoproj.io -o name` on a cluster without Argo CD |
| `crd_forbidden.txt` | synthetic | CRD read forbidden, namespaced list says the type is absent | `kubectl --as=dev get crd applications.argoproj.io -o name` on a cluster without Argo CD |
| `crd_forbidden_ns_ok.txt` | synthetic | CRD read forbidden, namespaced Application list answered | `kubectl --as=dev get crd applications.argoproj.io -o name` where `dev` can list Applications |
| `crd_forbidden_ns_forbidden.txt` | synthetic | CRD read and namespaced list both forbidden | `kubectl --as=dev get crd applications.argoproj.io -o name` where `dev` can read neither |
