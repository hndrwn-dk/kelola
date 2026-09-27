# M24 — Kubernetes workloads, read

Read-only cluster inventory through the host’s `kubectl`. Full design:
`docs/superpowers/specs/2026-09-27-m24-k8s-workloads-design.md`.

## Why the host, not a kubeconfig

kubenav stores cluster credentials on the device. Kelola already has an
SSH session to a machine that can reach the API. `kubectl` / `k3s
kubectl` come from HostFacts runtimes. No new secret at rest.

## Why JSON get

`kubectl get` wide columns change across versions. List parse is
`-o json` only. `describe`, events, and `top` are separate read probes.

## Out of scope

M25 mutate/destructive. M26 logs/exec. M27 apply. Fleet. Light theme.
