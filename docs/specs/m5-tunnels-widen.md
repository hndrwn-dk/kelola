# M5 — Widen tunnels (unlock block)

Local HTTP/HTTPS forwards already ship. This widening adds the rest of
the unlock-bundle tunnel surface: SOCKS5, remote forward, and
`kubectl port-forward` through the host binary.

Full design: `docs/superpowers/specs/2026-09-27-m5-tunnels-widen-design.md`.

## Kinds

`local` — existing `ssh -L`, phone loopback only.
`dynamic` — `ssh -D` SOCKS5 on `127.0.0.1`.
`remote` — `ssh -R`, listen on the host loopback only, dial the
saved destination from the phone.
`kubectl` — host `kubectl`/`k3s kubectl` `port-forward --address 127.0.0.1`,
then a local forward to that host port. No kubeconfig on the phone.

## Risk

Same as today's tunnels: mutate audit, loopback binds, never `0.0.0.0`.
Remote listen host is `localhost`. Open-in-browser stays on local and
kubectl only.

## Out of scope

M30 alerts. M8 NAT. Interactive kubectl. Light theme. B2.
