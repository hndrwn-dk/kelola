# M27 — Manifest view and guarded apply

Last Kubernetes leftover. Read `get -o yaml`, edit in a mono
editor, `kubectl diff` on the server, then `apply`. Binary still
comes from HostFacts. No kubeconfig on the phone. No fleet.

## Rules

- Namespace is always `-n` from the opened workload.
- YAML kind / name / namespace must match that workload or apply
  is refused.
- Pipe the document with `base64 -d` so a heredoc cannot collide.
- `diff` exit 1 means there is a diff, not a failure.
- Apply is destructive. Token is `namespace/name`. Presence required.
- Dry-run/diff is shown before the confirm sheet. Never apply silent.
