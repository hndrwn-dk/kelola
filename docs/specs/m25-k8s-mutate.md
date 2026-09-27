# M25 — Kubernetes workloads, mutate / destructive

Actions on a workload already listed by M24. Binary still comes from
HostFacts via `kubectlRun` (no `2>/dev/null`, so stderr is visible).

## Verbs

| Verb | Risk | Kinds |
|---|---|---|
| Restart (`rollout restart`) | mutate | deploy, sts, ds |
| Scale (`scale --replicas=N`) | mutate | deploy, sts |
| Delete (`delete --wait=false`) | destructive | all |

Scale is +1 / -1 from current `desired`. Scale to 0 is still mutate.

## Confirm

Mutate: `showMutateConfirm`. Delete: `DestructiveConfirmSheet` with
token `namespace/name`, plus `requireDestructivePresence`. Read-only
hosts are blocked by the dispatcher.

## Out of scope

M26 logs/exec. M27 apply/YAML. Fleet. Interactive `kubectl exec -it`.
