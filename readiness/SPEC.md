# Kelola — Production Readiness Specification

**Agentless Linux server administration from mobile.**
Version 0.2 · Owner: Hendrawan / Tursina Labs

v0.2 adds the **operator-velocity** layer missing from 0.1: incident sheets, correlation, snippets, global search, recents/resume, diagnostic packs, reversible mutate, and local widgets. Admin surfaces without these are a catalogue. With them, a tired person finishes an incident in two minutes.

---

## 1. Product definition

A Flutter mobile client that administers Linux hosts over SSH with **zero server-side installation**.

**Target hosts:** any machine running `sshd`. Homelab, VPS, public-cloud compute instances, small on-prem fleets.

**Non-goals (v1):**
- Not a terminal emulator (a terminal exists as an escape hatch, not the primary UI)
- Not a monitoring/alerting system (home-screen widgets show **cached** last-known state only)
- Not a fleet configuration manager (no Ansible replacement — snippets are personal, confirmed, audited)
- Not multi-user / no team features
- No cloud account, no telemetry, no server component

**Requirements on the managed host:**

| Requirement | Notes |
|---|---|
| `sshd` running | Already present on every Linux distribution |
| Public key in `authorized_keys` | Single line, added during enrollment |
| `sudo` | Only for state-mutating operations |
| `systemd-journal` group membership | Optional; grants sudo-free log reads |

Nothing is installed. This is the primary differentiator and belongs in the first line of the README.

---

## 2. Architecture

### 2.1 Layers

```
presentation/     Flutter widgets, Riverpod consumers
  screens/
  widgets/
domain/
  probes/         Typed command definitions (the core abstraction)
  facts/          HostFacts discovery + distro dispatch
  risk/           RiskLevel policy, confirmation gates
data/
  ssh/            dartssh2 session mgmt, pooling, ProxyJump
  keystore/       Platform channel to StrongBox / Secure Enclave
  db/             Drift: audit log, host inventory, cached facts
  llm/            Provider abstraction, on-device redaction
platform/
  android/        Keystore signer (Kotlin)
  ios/            Secure Enclave signer (Swift)
```

### 2.2 The Probe abstraction

Every interaction with a host is a typed `Probe`. No raw shell strings in the UI layer.

```dart
abstract class Probe<T> {
  String command(HostFacts facts);
  T parse(String stdout, String stderr, int exitCode);
  bool get needsSudo;
  RiskLevel get risk;        // read | mutate | destructive
  Duration get timeout;
}
```

**Why this matters:**
- Distro differences (`apt` vs `dnf`, `ufw` vs `firewalld`) resolve in `command()`, never in widgets
- `RiskLevel` mechanically drives read-only mode, confirmation dialogs, and audit records
- `parse()` is pure — unit-testable against captured fixtures without any network

### 2.3 HostFacts

Discovered once per connection, cached in Drift, invalidated on OS version change.

```dart
class HostFacts {
  final String osId;            // from /etc/os-release ID
  final String osVersionId;
  final InitSystem init;        // systemd | openrc | sysvinit
  final int? systemdVersion;
  final PackageManager pkg;     // apt | dnf | yum | zypper | apk | pacman
  final FirewallBackend fw;     // firewalld | ufw | nftables | iptables | none
  final bool hasJournald;
  final bool journalReadable;   // user in systemd-journal group
  final String arch;
}
```

Discovery is a single batched SSH exec, not eight round trips. Mobile latency makes chattiness expensive. The batch also records init binaries (`rc-service`, `openrc-run`) so Alpine/OpenRC hosts degrade instead of crashing when systemd is absent.

### 2.4 Core data sources

| Feature | Command | Output |
|---|---|---|
| Services | `systemctl list-units --type=service --all --output=json` | JSON |
| Unit detail | `systemctl show <unit> --output=json` | JSON |
| Logs | `journalctl -o json --no-pager -n N` | JSON lines |
| Disk | `df -PT` / `du -x -d1` | Fixed columns |
| Processes | `ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu` | Fixed columns |
| Packages (apt) | `apt-get -s upgrade` | Text |
| Packages (dnf) | `dnf check-update --refresh` | Text, exit 100 = updates |
| Firewall | `firewall-cmd --list-all` / `ufw status verbose` | Text |

JSON-native sources first. Text parsers need locale pinning (`LC_ALL=C`) and version-tagged fixtures.

---

## 3. Security design

### 3.1 Key management

- Keypair generated **on device, in hardware**: Android StrongBox / iOS Secure Enclave
- Private key is **non-exportable**; signing is biometric-gated per use
- **Algorithm: ECDSA P-256** (`ecdsa-sha2-nistp256`). Secure Enclave does not support Ed25519. Software Ed25519 offered as an explicitly-labelled fallback.
- No password authentication. Ever. Not as an option.
- Enrollment: app renders public key as QR + copyable `authorized_keys` line. Fully offline.

### 3.2 SSH hardening

- Host key TOFU with pinning; mismatch is a hard block with explicit re-pin flow
- `ProxyJump` / bastion chains supported from v1
- Strict cipher/KEX allowlist; no legacy algorithms
- Connection timeout and keepalive tuned for mobile networks
- Never log key material, sudo prompts, or command output containing credential patterns

### 3.3 Threat model summary

| Threat | Mitigation |
|---|---|
| Stolen unlocked phone | Biometric gate per signing operation |
| Rooted device | Non-exportable hardware key; attacker gets use, not the key |
| Malicious network | Host key pinning; SSH transport security |
| Shoulder surfing | No credential display anywhere in UI |
| Accidental destruction | RiskLevel gates + typed-hostname confirmation |
| Supply chain | Pinned deps, reproducible builds, signed releases |

### 3.4 Compliance features

- **Audit log**: every command — timestamp, host, user, command, exit code, duration. Drift-backed, exportable as JSON/CSV.
- **Read-only mode** per host: `RiskLevel.read` probes only, enforced at the dispatch layer.
- **No root login**: `PermitRootLogin` targets rejected at connection time with an explanation.
- **Session timeout** with biometric re-auth.
- **Posture warnings**: flag hosts still permitting password auth.

---

## 4. Twelve-Factor mapping

Honest assessment. Factors are evaluated against a mobile client, not a web service.

### ✅ Applies directly

**I. Codebase** — Single Git repo. Multiple deploys via Flutter flavors: `dev`, `staging`, `prod`, plus distribution variants (`fdroid`, `play` if permitted). One codebase, never a per-channel fork.

**II. Dependencies** — `pubspec.lock` committed and enforced in CI. No reliance on system-installed tooling. Native deps vendored or pinned by hash. `flutter pub get --enforce-lockfile` in CI.

**IV. Backing services** — SSH targets, Ollama endpoint, and LLM API are **attached resources**, addressed by user-supplied URL at runtime. No hardcoded endpoints. Swapping a local Ollama for a remote one is a config change with no code change.

**V. Build, release, run** — Strict separation. CI produces an immutable, signed artifact tagged `version+buildNumber`. Config is injected at build via `--dart-define`. **No runtime code loading, no over-the-air code push** — both would break reproducibility and F-Droid eligibility.

**IX. Disposability** — Critical on mobile. The app must survive process death at any moment:
- SSH sessions tolerate abrupt network loss and resume
- Audit log writes are transactional — never half-written
- Cold start to usable dashboard target: < 2s
- In-flight destructive operations are recorded *before* execution, with outcome reconciled on next connect

**X. Dev/prod parity** — Flavors differ only in config, never in code paths. CI runs the probe suite against a **real distro matrix** in containers (Ubuntu LTS, Debian stable, Rocky, openSUSE, Alpine) each running `sshd`.

**XI. Logs as event streams** — Structured logging to an in-memory ring buffer, exportable on demand. **No automatic upload** — mandatory for air-gapped use. Crash reporting is opt-in, off by default. The audit log is a separate, durable, user-owned artifact — not diagnostic logging.

**XII. Admin processes** — First-class, in-app, not hidden: Drift schema migrations, key rotation, audit export, host inventory backup/restore. Migrations run and are verified on launch.

### ⚠️ Applies with reinterpretation

**III. Config** — "Config in environment" for a mobile app means: **no secrets in the binary, ever.** Build-time config via `--dart-define`. Runtime config (host inventory, LLM endpoint, preferences) lives in device storage. Nothing sensitive is compiled in — verified by a CI secret-scanning step over the built artifact.

**VIII. Concurrency** — No process model to scale. The mapping is isolate-based concurrency: SSH I/O and output parsing run off the UI isolate; a bounded connection pool per host prevents fan-out from exhausting the SSH server's `MaxSessions`.

### ❌ Does not apply

**VI. Processes / stateless** — A mobile client is inherently stateful and single-user. The defensible partial mapping: no server-side session affinity, and all state is local and reconstructible. Claiming full compliance would be dishonest.

**VII. Port binding** — No service is exported. The only listener is the ephemeral local socket for SSH port-forwarding, which is a user-invoked feature, not an architectural export.

---

## 5. Technology decisions

| Concern | Choice | Rationale |
|---|---|---|
| UI | Flutter (stable channel) | Single codebase, existing expertise |
| State | Riverpod | Compile-safe DI, testable providers |
| SSH/SFTP/forwarding | `dartssh2` | Pure Dart, all three needs in one lib |
| Local DB | Drift (SQLite) | Typed queries, first-class migrations |
| Non-key storage | `flutter_secure_storage` | Metadata only — keys never touch it |
| Hardware keys | Platform channels (Kotlin/Swift) | No Dart library exposes StrongBox/SE |
| LLM (local) | Ollama HTTP | User-hosted, air-gap compatible |
| LLM (cloud) | BYO key, provider-agnostic | No vendor lock, no proxy service |
| CI | GitHub Actions | Free for public repos |
| Backend | **None** | Agentless is the product |

### 5.1 The critical unknown

`dartssh2` public-key auth requires signing a challenge. With the key in StrongBox/Secure Enclave, **the library never receives key material** — it needs a pluggable signing callback routed over a platform channel.

**This must be spiked before any UI work.** If unsupported: patch locally, contribute upstream, or fall back to libssh2 via FFI. If hardware-backed keys prove infeasible, the security differentiator collapses to parity with existing apps — a decision worth making in week one, not month three.

---

## 6. Testing strategy

| Layer | Approach | Gate |
|---|---|---|
| Probe parsers | Unit tests over captured fixtures, per distro + version | 90% line coverage |
| HostFacts | Fixture-driven, all supported distros | 100% branch |
| SSH layer | Integration vs. containerised `sshd` | All green |
| Distro matrix | CI job per distro, real commands, real output | All green |
| Risk gates | Property test: no `mutate`/`destructive` probe executes in read-only mode | Mandatory |
| Audit integrity | Every executed probe produces exactly one record | Mandatory |
| UI | Golden tests on key screens | Visual diff review |

**Fixture discipline:** every parser fixture is tagged with distro, version, and the tool version that produced it. `systemctl` JSON output has changed across systemd releases; parsers must be version-aware and tested as such.

---

## 7. Release engineering

- **Semantic versioning**; monotonic build numbers
- **Signed releases**; signing keys in CI secrets, never in repo
- **Reproducible builds** — required for F-Droid/IzzyOnDroid inclusion
- **Changelog** generated from conventional commits
- **Distribution**: IzzyOnDroid + GitHub Releases confirmed. **Google Play pending policy verification** — see §9.
- `SECURITY.md` with a disclosure address and response SLA
- Dependency and secret scanning on every PR

---

## 8. Milestones

| ID | Scope | Exit criteria |
|---|---|---|
| **M0** | Hardware key spike | SSH auth succeeds using a keystore-signed challenge. Go/no-go decision documented. |
| **M1** | Connect, HostFacts, dashboard, ProxyJump | Connects through a bastion to all matrix distros; facts correct |
| **M1.5** | Operator velocity — foundation | Recents, resume, global search index, host notes, pull-to-refresh, keep-awake, ssh_config import |
| **M2** | systemd management | List, filter, start/stop/restart/enable; failed-units view is the default landing screen; OpenRC degrades, does not crash |
| **M3** | journald | Filter by priority, unit, time range; export |
| **M4** | Audit log + read-only mode | Property tests pass; export verified |
| **M4.7** | Operator velocity — incident | Incident sheet, correlation, snippets, diagnostic pack, undo, widgets, OS shortcuts |
| **M5** | Port-forward + open in browser | Cockpit and Portainer reachable via tunnel |
| **M6** | Packages, firewall, disk triage | Works across full distro matrix including pacman |
| **M7** | LLM assist | Local + BYO providers; redaction verified; zero auto-execution |

M1–M4 + M1.5 + M4.5 + M4.6 + M4.7 constitutes public v1.0. Admin surfaces without operator velocity are a catalogue, not a 2am tool.

---

## 9. Open risks

| Risk | Impact | Action |
|---|---|---|
| Google Play prohibits remote-admin apps | Loses primary distribution channel | **Verify policy directly before M1.** A competing project warns that Play listing violates their terms. |
| dartssh2 lacks external signer hook | Kills hardware-key differentiator | M0 spike resolves this |
| Secure Enclave P-256 only | No Ed25519 in hardware | Accepted; ECDSA P-256 is standards-compliant |
| systemctl JSON schema drift | Parser breakage on new systemd | Version-tagged fixtures; graceful degradation to text parsing |
| Sudo password prompts | Blocks automation flows | Detect and surface; document NOPASSWD and polkit as optional hardening |
| Scope creep toward terminal-first | Becomes another SSH client | Terminal stays an escape hatch, never the primary surface |
| Scope creep toward Ansible | Becomes a config manager nobody asked for | Snippets are personal templates, confirmed per run, never applied as a fleet playbook |
| Widgets mistaken for monitoring | Support burden, battery drain, false "alerting" claims | Cache-only, off by default, stale age always labelled |

---

## 10. Definition of production ready

- [ ] All milestone exit criteria met through M4, plus M1.5 and M4.7
- [ ] Distro matrix green in CI, including Alpine OpenRC (no crash on service list)
- [ ] Zero secrets in built artifact (automated scan)
- [ ] Reproducible build verified by an independent third party
- [ ] Threat model reviewed; no unmitigated high-severity findings
- [ ] Audit log integrity property tests passing
- [ ] Cold start < 2s on a mid-range device; last host restored or hosts-by-attention shown
- [ ] Failed-unit attention chip opens the incident sheet in one tap
- [ ] Global search finds hosts, units, containers, files, and snippets
- [ ] Snippets never auto-execute; each run is a Probe and an audit record
- [ ] Accessibility pass: screen reader, contrast, touch targets
- [ ] i18n scaffolding in place (EN, ID)
- [ ] `SECURITY.md`, `LICENSE`, privacy statement published
- [ ] Play Store policy question resolved and documented

---

## 11. Operator productivity

The 0.1 spec defined *what* can be administered. It did not define *how fast a tired person gets from "something is wrong" to "I did the safe thing"*. That gap is the difference between a feature catalogue and a product people actually open at 2am.

Every item below is a first-class surface, not polish. M1.5 and M4.7 are in the v1.0 cut.

### 11.1 Incident sheet

Tapping an attention chip (failed units, disk ≥90%, container restart loop, unreachable) opens an **incident sheet**, not the generic dashboard.

The sheet stacks, in order:
1. What is broken — unit name, container name, filesystem, last-seen
2. Last 20 relevant log lines already filtered (unit + `err+`, or container logs)
3. Related entity if known from cache (listening port, owning PID, compose stack)
4. Two actions: **Explain** (M7, if configured) and the single most likely mutate (restart the failed unit, not "open services")

One tap from the hosts list. Five-hop navigation (hosts → dashboard → services → failed → detail → logs) is a failed incident UX.

### 11.2 Correlation

Entities link without a new SSH round-trip when the data is already in memory:

| From | To |
|---|---|
| Listening port | Owning PID → unit and/or container |
| Failed unit | Journal pre-filtered to that unit, `err+` |
| Restarting container | Container logs + compose stack siblings |
| Process | Unit (if a cgroup match is cached); never kill PID 1 / sshd |

Fresh correlation that needs a probe is `read`, cancellable, and cached for the session. A miss shows "not in cache — look up" rather than a spinner that blocks the sheet.

### 11.3 Recents, pins, resume

- Last 10 viewed objects per kind: hosts, units, files, containers, snippets
- Any of those can be **pinned** to that host's dashboard (max 6 pins)
- Cold start: if a session to the last host is still valid, restore it; otherwise the hosts list sorted by attention, not alphabet
- Android App Shortcuts and iOS Shortcuts: last host, that host's incident sheet, last active tunnel
- Deep links: `kelola://host/<id>/unit/<name>`, `kelola://host/<id>/incident`

### 11.4 Global search

One field, two scopes:

- **Across inventory** (hosts tab, tablet command palette, hardware keyboard `Ctrl+K` / `Cmd+K`): host alias, address, tags, notes
- **Inside a host**: unit names, container names, snippet names, recent file paths, pinned objects

Results grouped by kind. Selecting a unit opens detail. Search is local over cached facts and inventory; it does not SSH until the user opens a result.

### 11.5 Snippets (not Ansible)

User-authored command templates with typed placeholders (`{{unit}}`, `{{path}}`, `{{port}}`, `{{host}}`).

A snippet **is a Probe**:
- `RiskLevel` classified before display
- Never auto-runs, never runs across a fleet
- Every run is one audit record with the expanded command
- Stored locally; included in the encrypted backup; import/export as JSON — no cloud share

This is Termius-class productivity and how operators actually work on a phone. It is not a configuration manager. Fleet mode remains read-only.

Shipped starters (read or mutate, never destructive): "unit status", "listen on port", "disk snapshot (`df -PT`)", "vacuum journal (proposed only)". Users can delete them.

### 11.6 ssh_config import

Enrollment of 20 hosts by hand is how people abandon the app. M1 accepts a pasted or file-picked OpenSSH config (`Host` / `HostName` / `User` / `Port` / `ProxyJump`). Duplicate addresses merge with a prompt. Identity files on disk are **ignored** — Kelola uses its hardware key; the import copies routing, not credentials.

### 11.7 Config edit

On top of M4.6: before save, show a unified diff of the buffer against the `.bak` (or against the downloaded original if `.bak` was just created). Confirm is `mutate`. Paths under `/etc/ssh/` or `authorized_keys` stay `destructive` with the lockout guard.

### 11.8 Diagnostic pack

One action on a host or incident sheet: copy or share a **redacted** text bundle.

Contents: HostFacts, attention reasons, failed units, last 50 journal lines for those units, `df -PT`. Uses the M7 redaction table even when no LLM is configured. Never includes key material, sudo prompts, or snippet bodies that contain placeholder secrets. OS share sheet.

### 11.9 Reversible mutate

| Action | Undo window |
|---|---|
| Disable unit | 8s snackbar → re-enable |
| Stop (non-lockout unit) | 8s snackbar → start |
| Enable, start, restart, reload | No undo (restart *is* the recovery) |
| Kill TERM, delete, prune, firewall apply | No undo |

Undo is itself a Probe, biometric-gated if the original was, and audited. Destructive actions never offer undo. The snackbar must not cover the primary nav.

### 11.10 Session hygiene (mobile)

- Keep the screen awake during log follow, file transfer, active tunnel, and terminal
- Haptic on biometric success and when the destructive hostname field matches
- Stale-while-revalidate for HostFacts and unit lists; age labelled (`updated 40s ago`)
- Pull-to-refresh on every list
- Connection RTT of the last successful exec shown on the host dashboard (one number, not a chart)

### 11.11 Host notes

Free-text note per host, local only, shown on the dashboard under the title. For "living-room NAS — do not stop smbd". Searchable. In the encrypted backup.

### 11.12 Widgets (cached, off by default)

A home-screen widget showing the worst host and failed-unit count from the **last successful** refresh. Stale age is visible. Tap opens the incident sheet. This is not monitoring: no background polling beyond what the OS allows for widget updates, no alerts, no sound. Off by default so battery and "is this an alerting product?" stay honest.

### 11.13 Non-systemd hosts

Alpine is in the CI matrix. `HostFacts.init == openrc` uses `rc-status` / `rc-service` for list and start/stop/restart. Unknown init shows a dedicated empty state ("this host is not systemd — use the shell") rather than a parser crash. Full OpenRC feature parity is out of scope; not crashing is not.
