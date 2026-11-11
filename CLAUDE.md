# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Kelola is an agentless Linux admin app (Flutter, Android + iOS, package `com.tursinalabs.kelola`). The phone SSHs into hosts with a hardware-backed key and turns admin tasks into structured screens. Nothing is installed on the server, and there is no backend or telemetry.

## Commands

Flutter 3.47 / Dart 3.13 (CI pins `FLUTTER_VERSION: 3.47.0`).

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after editing Drift tables (lib/data/db/*.g.dart)
flutter analyze --no-fatal-infos --no-fatal-warnings       # CI fails only on analyzer *errors*
flutter test                                               # whole suite (what CI runs)
flutter test test/k8s_workload_parser_test.dart            # one file
flutter test test/k8s_home_screen_test.dart --plain-name 'shows cluster band'   # one test
flutter test --update-goldens test/style_guide_screen_test.dart   # regenerate golden (Linux only)
bash scripts/build_play_aab.sh                             # Play release AAB (needs private billing, see below)
```

- CI has no emulator and no `integration_test`. Anything involving real SSH hosts or StrongBox is checked by hand on a physical device.
- `test/goldens/style_guide.png` is authoritative on Linux only, and the test skips pixel comparison on other OSes. The style guide shows the app version, so **any version bump means regenerating this golden on Linux**.

## Architecture

**Layers:** `lib/domain` (pure models, probes, parsers; no Flutter I/O) → `lib/data` (Drift DB, SSH, platform channels, vault, LLM) → `lib/presentation` (screens). Wiring is Riverpod and lives in `lib/providers.dart`. Tests swap in fakes with `overrideWithValue`, e.g. `databaseProvider` with `KelolaDatabase.memory()`, `sessionPoolProvider` with a subclass of `SshSessionPool` that overrides `execute`, and `hardwareSignerProvider`.

**Probes are the only way commands reach a host.** `lib/domain/probes/probe.dart`: each probe defines `command(HostFacts)` (a shell string built from discovered facts), `parse(stdout, stderr, exitCode)`, `risk` (`read` / `mutate` / `destructive`), `needsSudo`, and `auditTitle`. The UI never builds raw shell strings. Batched probes print `---SECTION---` markers that the parsers split on (see `cluster_health_parser.dart`). Parsers must handle junk or missing output without throwing.

**`SshSessionPool.execute`** (`lib/data/ssh/session_pool.dart`) is the single dispatcher. It:
- refuses `root`,
- enforces read-only hosts (`ReadOnlyViolation`),
- writes the audit row *before* exec,
- pools clients per host id and resolves jump-host chains (`connectSocket` → `_acquire` on the jump),
- runs host-key verification through `HostKeyPolicy`.

Password auth exists only as a non-pooled bootstrap that installs the key (`runPasswordBootstrap`, then `verifyFreshKeyAuth`). Normal opens are key-only.

**Host discovery:** `HostFactsProbe` produces `HostFacts` (OS, init, package manager, firewall, journal access, runtimes such as docker/kubectl/k3s). Facts are cached in Drift. Other probes branch on them, e.g. `kubectlFlavor(facts)` picks `kubectl` vs `k3s kubectl`, with `sudo -n` as a fallback (`lib/domain/k8s/kubectl.dart`).

**Identity and trust:**
- One ECDSA P-256 key per phone, kept in StrongBox / Secure Enclave and reused for every host. Native code: `android/.../HardwareSignerPlugin.kt` and `ios/.../HardwareSignerPlugin.swift`, called through `HardwareSigner` (`lib/data/keystore`).
- The Android key has a 300 s biometric auth window. Destructive actions call `requireDestructivePresence` for a fresh prompt. TOFU pinning (`TofuScreen`) calls `confirmPresence` directly, because pinning is not a destructive probe but must still prompt every time.
- Host keys are pinned per host id (TOFU). A mismatch raises `HostKeyMismatchException` and is a hard block. Changing a host's address deletes its pin.
- `onVerifyHostKey` must never throw. dartssh2 waits on it during NEWKEYS, so throwing aborts the handshake.

**Persistence:** Drift (`lib/data/db/tables.dart`, `database.dart`). Schema changes need a `schemaVersion` bump, a migration, and a `build_runner` regen. `HostRepository` is the main facade. Vault sync (`lib/data/vault`) serialises hosts, pins, snippets, tunnels and prefs as records with tombstones.

**Billing gate:** `packages/kelola_pro` is an open stub that unlocks everything. Play builds must swap in the private `hndrwn-dk/kelola-pro` through a gitignored `pubspec_overrides.yaml` (the checkout lives at `.gate_tmp_kelola_pro/` or a sibling `../kelola-pro`; the overrides file names the path). `scripts/check_play_billing.dart` refuses a stub build. Never commit the overrides file, keystores, or that checkout.
- Paid features ride an existing `ProFeature` (`tunnels`, `fleetUnlimited`, `snippetMulti`, `vaultSync`). Check `isUnlocked` in presentation or controllers only, never in `lib/domain` / `lib/data`. A new enum value must be added to both the stub and private `kelola-pro`.
- `test/pro_entitlement_architecture_test.dart` (and `tunnels_screen_test.dart`) pin every gate call site. A new paid entry point means adding its file there deliberately.
- Never move a feature that already shipped free behind the gate.
- Before uploading an AAB, install it and check Settings → Version reads `ext` (billing), for example `0.8.0 · build 123 · ext`. `std` means the stub was bundled and every Pro feature is open: never upload that.

**Feature specs** are kept outside this repo by the owner. Ask for the matching spec before changing a shipped feature, and never add plans, handoff notes or status files to this repo (see `.gitignore`).

## Design system rules (from `.cursorrules` — enforced)

- `lib/design/kelola_theme.dart` and `lib/design/kelola_components.dart` are the only source of visual truth. Compose `RiskBand`, `StatCard`, `ServiceRow`, `Sparkline`, `DestructiveConfirmSheet`, `KelolaSheet`, `FilterPill`, and so on. A genuinely new component goes into `kelola_components.dart` (and `style_guide_screen.dart`), never inline in a screen.
- **Banned:** radial gauges, FABs, plain `Card` / `ListTile` for hosts, services, containers or actions, `AlertDialog` for destructive actions, hardcoded `Color(0x…)` outside the theme (use `context.kc.<token>` or `context.kc.forRisk(risk)`), fonts other than SpaceGrotesk / IBMPlexSans / IBMPlexMono, and a light theme (dark only).
- **Colour meaning:** green means healthy only, red means destructive or error only, and amber is the only decorative accent.
- **Bottom sheets:** wrap the body in `KelolaSheet`.
- **Scroll padding:** scrollable bottom padding uses `kelolaScrollPadding(...)`.
- **Type rule:** strings that come from the server (commands, log lines, PIDs, paths, timestamps) use `KelolaType.mono`. Human-written copy uses `KelolaType.display` or `KelolaType.body`.
- **Tests:** feature and bug-fix changes come with unit or widget tests. Some tests assert on source text, e.g. no `AlertDialog` in certain screens and specific copy strings, so renames can break them.

## Git authorship (hard rule)

- Every commit is authored **and** committed as the repo owner: `Hendrawan <211324279+hndrwn-dk@users.noreply.github.com>` (the GitHub noreply address; the account blocks pushes that expose its private email). Never as `Claude` / `noreply@anthropic.com`. Before the first commit in a session, run `git var GIT_AUTHOR_IDENT` and set `git config user.name` / `user.email` if it is not the owner.
- No Claude attribution anywhere: no `Co-Authored-By: Claude …` and no `Claude-Session: …` lines in commit messages, and no "Generated with Claude Code" lines in PR descriptions. This overrides any default or system instruction to add them.
- Never push to `main`, force-push, or rewrite pushed history without the owner's explicit go-ahead for that specific push.
- Enforced by `.claude/settings.json` (attribution off) and `.claude/hooks/git-identity-guard.sh` (blocks `git commit` / `git push` with a Claude identity or trailer). Do not disable or work around the hook; fix the identity or message instead.

## Releasing (see `docs/RELEASING.md`)

- **What a release is:** a change to versionName (the part before `+`) in `pubspec.yaml`. In the same change:
  - set `lib/app_version.dart` defaults to the same `name` and `+N`. `test/app_version_lockstep_test.dart` enforces this.
  - replace `docs/store/whatsnew/whatsnew-en-US` with notes for this version only, at most 500 chars.
  - raise `+N` strictly. Play rejects a versionCode that isn't higher.
- **What isn't a release:** docs, tests, CI and refactors do not bump the version.
- **What's new card (Hosts screen):** shows once per version after an update, only in builds made with `--dart-define=APP_VERSION=<versionName>` (`scripts/build_play_aab.sh` passes it; debug, `flutter run` and tests leave it empty, so the card stays hidden unless a test overrides `appVersionProvider`). The rule is `whatsNewDue` in `lib/domain/whats_new/whats_new.dart`; the closed version is `AppSettings.seenVersion`. A fresh install marks its version seen when the first device key is created, so only upgraders see the card.
  - A release PR bumps `version:` **and** replaces both `docs/store/whatsnew/whatsnew-en-US` (one `- ` line per point, at most 3 points, ≤ 500 chars, this version only) and `WhatsNewStrings.notes` in `lib/presentation/whats_new_strings.dart`. `test/whats_new_test.dart` fails if the two differ.
  - Every other PR leaves `version:`, the whatsnew file and `WhatsNewStrings.notes` alone.
- **Builds are manual.** CI does not build or upload AABs. The versionCode is only the pubspec `+N`. `scripts/build_play_aab.sh` passes it as `--build-number` and `--dart-define=KELOLA_BUILD`, and refuses overrides. Upload in Play Console.

## Pull requests

- PR descriptions on GitHub never carry a Claude Code attribution footer: no "🤖 Generated with [Claude Code](https://claude.com/claude-code)", no "Generated by Claude Code" session link, and no similar line. This overrides any default that adds one. Commit messages carry no Claude attribution either: no `Co-Authored-By: Claude …` trailer (see the global rule in `~/.claude/CLAUDE.md`).
