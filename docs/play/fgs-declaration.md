# Play Console — Foreground service declaration (M5 tunnels)

Fill this under **Monitor and improve → App content → Foreground service**. The form applies to every typed FGS when targeting Android 14+; `specialUse` adds a free-form justification (and the matching manifest property), not a separate form.

**Type in use:** `specialUse`  
**Use case on the form:** Other  
**Permissions added for M5:** `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS`  
**Not used:** `connectedDevice` / `CHANGE_NETWORK_*` / Bluetooth / USB / NFC — Kelola does not hold those prerequisites and will not add them as padding.

---

## Play Console single field (paste)

Use this in **Describe your app's use of this permission, including why the task must start immediately and cannot be paused or restarted**. ~650 characters.

Kelola keeps user-started SSH local port forwards alive so admin UIs on the user's own Linux hosts stay reachable at 127.0.0.1 in the phone browser. An ongoing notification shows active tunnels and Stop all. The service must start as soon as a tunnel starts: if deferred, Android can freeze or kill the process when the user leaves Kelola for the browser, dropping the SSH session and local URL. Pause or restart closes those sockets and breaks the in-browser session until the user starts each tunnel again. The service stops when the last tunnel is stopped, idles out, or the app is removed from Recents. No other FGS type fits (not media, location, health, sync, or a connected accessory).

---

## Description (long reference)

Kelola opens local SSH port forwards so the user can reach admin UIs on their own Linux hosts (for example Cockpit or Grafana) from the phone browser. While one or more forwards are active, the app runs a foreground service with an ongoing notification that shows how many tunnels are open and which host aliases they belong to. The service exists only to keep those SSH sessions and loopback listeners alive and to give the user a single **Stop all** action. Listening sockets bind only to 127.0.0.1. The service stops as soon as the last tunnel closes (user stop, idle timeout after no forwarded connections, or app removal from recents).

## Impact if deferred / not started

Without the foreground service, the system can kill or freeze the process while the user is in another app (for example reading a dashboard in Chrome). Active forwards drop, the loopback URL stops working, and the user must return to Kelola and start each target again. Deferring the service therefore breaks the core “open in browser and keep working” flow for tunnels.

## Impact if interrupted

If the system stops the service while tunnels are active, all local listeners and SSH forward channels are closed. In-browser sessions to those URLs fail until the user reopens the targets from Kelola. No host-side mutation occurs (forwards are read-only pathing); the only loss is connectivity through the phone.

## specialUse justification (paste)

Kelola’s tunnel feature maintains long-lived SSH local port forwards to user-managed servers. No other foreground service type fits: this is not media playback, location tracking, health, data sync, or a connection to a Bluetooth/USB/NFC accessory. The work is “keep an SSH session and loopback listener alive until the user stops it, it idles out, or the task is removed.” `specialUse` is the accurate type. The service starts only when at least one tunnel is listening and stops within one second of the last tunnel closing.

## Demo video — shot list

Record on a physical device or emulator with notification permission granted (and a second take with permission denied if you want to show the inline explainer). Suggested length: 60–90 seconds. Show the notification shade clearly.

1. **Cold start** — Open Kelola; no tunnel notification.
2. **Start one tunnel** — Host dashboard → Tunnels → Start a saved target (e.g. Cockpit). Show the ongoing notification: `1 tunnel active · <alias>`.
3. **Open in browser** — Open the local URL. Prefer an HTTP target (e.g. Grafana) or cut away as soon as the browser loads so a full-page HTTPS cert interstitial is not the hero frame. The in-app HTTPS warning copy stays; it does not need to dominate the demo.
4. **Second tunnel** — Start another target (same or other host). Notification updates to `2 tunnels active · …`.
5. **Stop one** — Stop from the tunnels screen; notification count drops to 1; service remains.
6. **Stop all** — From the notification action **Stop all**; notification disappears; service gone.
7. **Idle countdown (optional but strong)** — Start one tunnel, leave `openChannels` at 0 until `idleClosing`; show countdown on the tunnels row and on the notification; either let it close or generate traffic (browser reload) to cancel.
8. **Task removed (optional)** — Start a tunnel, remove Kelola from recents; confirm notification clears (termination path).

Do **not** show Fleet starting tunnels. Do **not** show password auth. Do **not** claim the listener is reachable off-device.

## Checklist before submit

- [ ] Manifest: `foregroundServiceType="specialUse"` and special-use property set
- [ ] Manifest permissions match `tunnel_manifest_permissions_test` (no connected-device prerequisites)
- [ ] Video shows notification + Stop all + service ending when work ends
- [ ] Declaration text matches what the build actually does (idle close, loopback-only, no background-as-close)
