# Support, legal, and Play feedback (Tester Community)

Settings must expose Help, Privacy, Terms, Play review, and Share so
closed testers can find support without a new backend.

## Goal

Play Tester Community checklist:

1. In-app Help / FAQ for common questions.
2. Privacy and Terms reachable from Settings.
3. Feedback via the existing Play Store review field.
4. Share / invite a friend using the same Play listing.

## Constraints

- Compose `HostGroupTray` + `ServiceRow`. No `ListTile`, `Card`, FAB,
  or `AlertDialog`.
- Human copy uses `KelolaType.display` / `KelolaType.body`.
- Open URLs with `url_launcher` in `LaunchMode.externalApplication`
  (same as tunnels). No in-app WebView.
- Share with existing `share_plus` (same as vault / snippets).
- Dark theme only. English UI (matches the rest of the app).
- No new Play In-App Review API, mailto, or website form.

## Information architecture

Keep the existing **App** tray unchanged. Add a **Support** tray below
it on `SettingsScreen`:

| Row | Meta | Action |
|---|---|---|
| Help & FAQ | common questions | push `HelpScreen` |
| Privacy | tursinalabs.com | open privacy URL |
| Terms of Service | tursinalabs.com | open terms URL |
| Rate & review | Play Store | open Play listing |
| Share Kelola | invite a friend | system share sheet |

## Canonical URLs

Single source of truth (domain constants, not scattered string literals
in widgets):

- Play: `https://play.google.com/store/apps/details?id=com.tursinalabs.kelola`
- Privacy: `https://www.tursinalabs.com/kelola/privacy`
- Terms: `https://www.tursinalabs.com/kelola/terms`

Share text (human-written + the Play URL), subject `Kelola`:

```
Kelola — agentless Linux admin from your phone.
https://play.google.com/store/apps/details?id=com.tursinalabs.kelola
```

## Help screen

New file `lib/presentation/screens/help_screen.dart`. Route
`HelpScreen`: `KelolaWashScaffold`, back, title **Help**,
`kelolaScrollPadding`. Five static `ServiceRow`s (`RiskLevel.read`):

1. **How do I add a server?** — On Hosts, add a host (address, user,
   port). Kelola talks to it over SSH. Nothing is installed on the
   server.
2. **Where are my SSH keys?** — Keys stay on this phone. They are not
   uploaded and are not in a default vault export.
3. **What does vault export include?** — Hosts, snippets, and settings.
   Passwords, env values, and snippet bodies stay off the blob unless
   you turn on include secrets.
4. **How does app lock work?** — Optional. Uses the device screen lock.
   If the platform errors, Kelola stays locked.
5. **How do I report a problem?** — Settings → Rate & review opens the
   Play listing. Use the review field there.

`name` is the question, `detail` is the answer. No accordion.

## Data flow

- Settings injects optional `launchUrl` and `share` callbacks so widget
  tests do not hit the plugin. Production defaults: `launchUrl(...,
  mode: LaunchMode.externalApplication)` and `Share.share`.
- Failed URL open or share: `SnackBar` with `Could not open link.`
  (or `Could not share.` for the share path). No crash.
- Help is a push route (`MaterialPageRoute`), not a sheet.

## Testing

- Settings shows the five Support rows.
- Help screen shows the five question strings.
- Tapping Privacy / Terms / Rate & review calls `launchUrl` with the
  matching URI.
- Tapping Share Kelola calls share with text that contains the Play URL.
- Failed launch shows a SnackBar.

## Out of scope

- Play In-App Review API or a write-review-only deep link.
- In-app feedback form, email, or a new tursinalabs.com Help page.
- Localization / Indonesian UI.
- Light theme.
- Version bump or Play AAB (separate release step).
