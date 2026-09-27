# M26 — Kubernetes logs and exec

Read logs and run one command in a pod through the host’s kubectl.
No PTY. No kubeconfig on the phone.

## Logs

`RiskLevel.read`. `kubectl logs <kind>/<name> --tail=80 --timestamps`.
Shown as mono `SelectableText`. One-shot; follow is deferred.

## Exec

Pods only. `RiskLevel.mutate` like the Command sheet.
`kubectl exec <pod> -- sh -c '<quoted>'`. KelolaSheet: mono input,
mono output. Not recorded in host command history.

## Out of scope

M27 apply. Interactive `-it`. Fleet. Log follow.
