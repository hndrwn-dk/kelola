# M5 — Tunnels (decision record)

Local SSH port forwarding with named presets, an active-tunnel list, and open-in-browser. Full design: `docs/superpowers/specs/2026-09-13-m5-tunnels-design.md`.

## Why loopback-only

The browser talks to a listener on the phone. For HTTP that hop is plaintext. Binding `InternetAddress.loopbackIPv4` (ephemeral port) keeps that hop on-device. The phone↔server hop is encrypted by SSH. Never `0.0.0.0` / `anyIPv4` / a fixed local port.

## Why a dedicated tunnel client per host

Exec uses a small pooled set of SSH clients (three per host). A forward is long-lived and would starve probes if it sat in that pool. `SshSessionPool` exposes a separate tunnel client per host; forwards use `forwardLocal` the same way ProxyJump does.

## Why tunnels are not Probes

`Probe<T>` is exec: build a command, parse stdout/stderr/exit. A tunnel owns a `ServerSocket`, accepted connections, and bidirectional pipes. Putting it in the probe list would force the wrong lifecycle and invite Fleet to call it. Fleet stays read-only; tunnels never appear under `lib/domain/fleet/`.

## Why active tunnels are not persisted

Local ports are OS-assigned. After process death there is no listener and no SSH channel. Restoring a row would claim a URL that does not work. Cold start always shows an empty active list; the user starts targets again. Saved **targets** (labels, remote host/port/scheme/path) are persisted per host.

## Idle close (not background grace)

A tunnel with `openChannels == 0` for the idle window (default 10 min, range 2–60 on read and write, settings API only) closes itself. `ActiveTunnel.closesAtUtc` is the stream-facing deadline; UI and notification derive the countdown from it (no mirrored private timer). One minute before expiry, state becomes `idleClosing`. Closure triggers are only: explicit stop, idle timeout, app termination. App background does not close tunnels. The dedicated tunnel client uses the same 30s SSH keep-alive as exec so idle listeners are not silently dropped by NATs.

## Entitlement seam (what it does / does not)

`Entitlement.tunnelsUnlocked` is read once in production: the host-dashboard Tunnels tile. Locked → tile stays visible → short explainer sheet. Domain tunnels, the engine, and repositories do not import entitlement. Default is `OpenEntitlement` (everything unlocked for source, debug, and tests). This change does **not** add Play Billing, product IDs, or store calls.

## Persistence notes

Saved targets store `scheme` as the text `http` / `https` (never an enum ordinal). Audit gains nullable `closeReason`; tunnel open/close leave `exitCode` null and set `closeReason` so they are not orphans. Idle minutes clamp to 2–60 on both read and write.

## Android FGS

While any tunnel is active, a `specialUse` foreground service runs with an ongoing notification and Stop all. Chosen over `connectedDevice` so Kelola does not declare unused network/BT/USB permissions that `connectedDevice` requires at runtime. See `docs/play/fgs-declaration.md`.
