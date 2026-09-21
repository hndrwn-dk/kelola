# M4.7 remainder — shortcuts, haptics, keep-awake

Android launcher shortcuts, two haptic pulses, and display keep-awake. Full design: `docs/superpowers/specs/2026-09-21-m47-shortcuts-haptics-keep-awake-design.md`.

## Why one parser

Widgets already emit `kelola://host/<id>/incident`. Shortcuts must be `ACTION_VIEW` intents to the same URIs so cold start (`BootGate`) and warm start (`onNewIntent`) stay one path. Native `ShortcutManager`, not `quick_actions`.

## Why saved targets, not last active tunnel

Active forwards die with the process. A shortcut to a dead local port would lie. A host with at least one saved tunnel target is the durable “has a tunnel” signal. No `lastTunnelId` column.

## Why Dart-side haptics

`confirmPresence` / `sign` succeeding is the Dart signal that the native prompt succeeded. One `HapticFeedback.lightImpact()` there. Type-to-confirm fires `mediumImpact` on false→true match only. Kotlin must not also vibrate.

## Why ref-counted wakelock_plus

Follow, transfer, tunnels, and the command sheet can overlap. Display `FLAG_KEEP_SCREEN_ON` only while the hold set is non-empty. Tunnels are app-wide (`activeTunnelsProvider`), not tied to `TunnelsScreen`. Idle SSH pool does not hold the lock. No `WAKE_LOCK` permission.

## Out of scope

B2 Play Billing (until production-approved Play release). iOS Siri Shortcuts. M8 / M9 / M11 / M13 / M3 leftovers.
