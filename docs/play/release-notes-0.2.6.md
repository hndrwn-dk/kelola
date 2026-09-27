# Play Console — release notes (0.2.6)

**Version name:** 0.2.6  
**Version code:** 9  
**Track:** Alpha (or Internal)  
**AAB:** `bundles_release/v0.2.6+9/app-release-0.2.6+9.aab` (gitignored; local only)

**Play paste:** `bundles_release/play-console/PLAY_STORE_v0.2.6+9.txt`

## Short description (Play “Release notes”, en-US)

Kubernetes on the host dashboard: list cluster objects through this machine’s kubectl or k3s, then restart, scale, delete, read logs, or run one command in a pod. No kubeconfig on the phone. Also: app lock, command history with local autocomplete, and per-host snippet scope.

## Longer notes (optional / changelog)

What’s new in 0.2.6:

- **Kubernetes** — New TOOLS tile (`Kubernetes` / `cluster`). Lists deploy, sts, ds, job, cron, and pod from the host’s `kubectl` or `k3s kubectl`. No kubeconfig stored on the phone. Dashboard does not read `facts.runtimes`.
- **Read** — JSON inventory, describe, events, and `top` (metrics-server optional). Filters: namespace, kind, not-ready.
- **Mutate / delete** — Rollout restart, scale ±1, delete with typed confirm and presence. Read-only hosts stay blocked.
- **Logs / exec** — Last 80 log lines. One-shot `exec` in a pod (no PTY, not host command history).
- **App lock (M29)** — Optional OS credential overlay; default off; fail-open.
- **Command sheet** — Per-host history reuse and local autocomplete (no LLM).
- **Snippets** — Host / tag scope and dashboard startup offers (never auto-run).

## Play App content — FGS

If not already submitted for this package: paste from `docs/play/fgs-declaration.md` (specialUse justification, impact if deferred/interrupted, demo shot list).

## Build

```bash
# Requires pubspec_overrides.yaml pointing kelola_pro at the private billing
# package. The check refuses a std-stub AAB (all Pro unlocked).
bash scripts/build_play_aab.sh
```

Signed with `android/key.properties` → upload keystore.

Do **not** run bare `flutter build appbundle --release` for Play — that skips the billing gate.
