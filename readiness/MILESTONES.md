# Kelola — Milestone Engineering Specs

Companion to `SPEC.md`. Each milestone defines scope, design, exit criteria, and risks.

**Rule:** a milestone is not done until its exit criteria pass in CI, not on a developer's machine.

v0.2 adds **M1.5** (resume, search, notes, ssh_config) and **M4.7** (incident, snippets, correlation, diagnostic pack, undo, widget). Both are in the public v1.0 cut.

---

## M0 — Hardware key spike

**Duration:** 1 week. **Type:** Spike. Throwaway code permitted.

### Objective
Prove that an SSH session can authenticate using a private key that never leaves Android StrongBox / iOS Secure Enclave.

### The problem
SSH public-key auth requires signing a challenge blob:

```
string    session identifier
byte      SSH_MSG_USERAUTH_REQUEST
string    user name
string    service name
string    "publickey"
boolean   TRUE
string    public key algorithm name
string    public key blob
```

The client signs this with the private key. If the key is in hardware, `dartssh2` never holds key material — it needs to delegate signing.

### Investigation order
1. Read `dartssh2` source for an injectable signer interface on `SSHKeyPair`
2. If absent, evaluate the cost of a local patch adding a `SSHSigner` callback
3. If patching is unclean, evaluate libssh2 via `dart:ffi` with a custom auth callback
4. Fallback: software-held Ed25519 in `flutter_secure_storage` (parity with competitors — a materially weaker product)

### Platform channel contract

```dart
abstract class HardwareSigner {
  Future<String> generateKey(String alias);   // returns OpenSSH public key
  Future<Uint8List> sign(String alias, Uint8List data);  // biometric-gated
  Future<bool> keyExists(String alias);
  Future<void> deleteKey(String alias);
}
```

**Android:** `KeyPairGenerator` with `KeyProperties.KEY_ALGORITHM_EC`, P-256, `setIsStrongBoxBacked(true)`, `setUserAuthenticationRequired(true)`. Sign with `Signature.getInstance("SHA256withECDSA")`.

**iOS:** `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`, `kSecAttrKeyTypeECSECPrimeRandom`, 256-bit. Sign with `SecKeyCreateSignature` / `ecdsaSignatureMessageX962SHA256`.

**Format conversion required:** both platforms emit ASN.1 DER signatures. SSH wire format for `ecdsa-sha2-nistp256` is `mpint r || mpint s`. Write and unit-test this converter — it is a common source of silent auth failures.

### Exit criteria
- [ ] Key generated in StrongBox on a physical Android device (verify attestation)
- [ ] Key generated in Secure Enclave on a physical iPhone
- [ ] `ssh` auth succeeds against OpenSSH 8.x and 9.x using the hardware key
- [ ] Biometric prompt appears on each signing operation
- [ ] Key is confirmed non-exportable (attempt export, expect failure)
- [ ] DER→SSH signature converter has round-trip unit tests
- [ ] **Written go/no-go decision committed to the repo**

### Risk
If no-go, the product's headline security claim disappears. Decide explicitly whether to proceed with software keys or reconsider the project — do not drift into it by default.

---

## M1 — Connection, HostFacts, dashboard

**Duration:** 3 weeks.

### Scope
- Host inventory: add, edit, delete, reorder
- **ssh_config import**: paste or pick a file; `Host` / `HostName` / `User` / `Port` / `ProxyJump` only. IdentityFile ignored — Kelola uses the hardware key
- Key enrollment flow with QR display
- Connection with ProxyJump / bastion chains
- Host key TOFU with pinning
- HostFacts discovery
- Dashboard: uptime, load, memory, disk summary, failed unit count

### Enrollment UX
1. User adds a host: address, port, username, optional jump host
2. App generates (or reuses) a hardware key
3. App displays the public key as **QR code** plus a copyable one-liner:
   `echo 'ecdsa-sha2-nistp256 AAAA...' >> ~/.ssh/authorized_keys`
4. User applies it on the server by any means — no network dependency
5. "Test connection" verifies and pins the host key

### HostFacts batched discovery
One SSH exec, not eight:

```sh
LC_ALL=C; echo "---OS---"; cat /etc/os-release
echo "---INIT---"; readlink -f /sbin/init 2>/dev/null; systemctl --version 2>/dev/null | head -1
command -v rc-service openrc-run 2>/dev/null
echo "---PKG---"; command -v apt-get dnf yum zypper apk pacman 2>/dev/null
echo "---FW---"; command -v firewall-cmd ufw nft iptables 2>/dev/null
echo "---JOURNAL---"; id -nG
echo "---ARCH---"; uname -m
```

Parse into `HostFacts`, persist to Drift, invalidate on `os-release` change.

### Connection management
- Bounded pool: max 3 concurrent sessions per host (respect `MaxSessions`)
- Keepalive every 30s; reconnect with exponential backoff
- All SSH I/O on a background isolate
- Cipher allowlist: `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`. KEX: `curve25519-sha256`. No legacy fallback.

### Host key policy
| State | Behaviour |
|---|---|
| Unknown | Show fingerprint, require explicit accept, pin |
| Match | Connect silently |
| Mismatch | **Hard block.** Full-screen warning, explicit re-pin flow, audit record |

### Exit criteria
- [ ] Connects to every distro in the CI matrix
- [ ] Connects through a two-hop bastion chain
- [ ] HostFacts correct for all matrix distros (fixture-verified)
- [ ] Host key mismatch blocks connection and writes an audit record
- [ ] Dashboard cold-loads in under 2s on a mid-range device
- [ ] Network loss mid-connection recovers without app restart
- [ ] OpenSSH config import creates the right hosts, jump chains, and ignores IdentityFile

---

## M1.5 — Operator velocity, foundation

**Duration:** 1 week. **Ships with M1**, not after polish. Without this, the dashboard is a status page.

### Scope
- Recents: last 10 hosts, units, files, containers
- Pins: up to 6 objects on a host dashboard
- Resume last host on cold start when the session is still valid; otherwise hosts sorted by attention
- Host notes (local, searchable, in encrypted backup)
- Global search over inventory (alias, address, notes, tags)
- Pull-to-refresh on every list; stale age labelled
- Last-exec RTT on the host dashboard
- Keep-awake during in-flight SSH that the user is watching (connect, discovery)
- Deep link `kelola://host/<id>`

In-host search (units, containers, snippets) lands in M4.7 once those objects exist.

### Exit criteria
- [ ] Killing the app and relaunching restores the last host if the pool still holds a session
- [ ] Hosts list sorts unreachable and failed-unit hosts above healthy ones
- [ ] Search is local — verified: airplane mode still finds inventory
- [ ] ssh_config IdentityFile paths never appear in the DB or audit log

---

## M2 — systemd service management

**Duration:** 2 weeks.

### Scope
- Unit list with filter (state, type, enabled) and search
- **Failed units as the default landing view**
- Unit detail: status, recent logs, dependencies, unit file
- Actions: start, stop, restart, reload, enable, disable
- **OpenRC degradation:** if `HostFacts.init == openrc`, list via `rc-status -a` and mutate via `rc-service <name> <verb>`. Unknown init: empty state pointing at the shell, never a parser exception.

### Commands
```sh
systemctl list-units --type=service --all --output=json
systemctl show <unit> --output=json
systemctl list-unit-files --type=service --output=json
sudo systemctl <verb> <unit>
```

### Version handling
`--output=json` requires systemd 246+ (2020). For older systems fall back to `--no-legend --plain` column parsing. `HostFacts.systemdVersion` selects the parser. Fixtures required for both paths.

### Risk classification
| Action | Risk |
|---|---|
| list, show | `read` |
| start, restart, reload | `mutate` |
| stop, disable | `mutate` |
| stop on `sshd`, `NetworkManager`, `systemd-networkd` | `destructive` — self-lockout guard |

**Self-lockout guard:** stopping the network or SSH service must warn explicitly that it will end the session and may make the host unreachable. This is the single most likely way a user destroys their own access.

### Exit criteria
- [ ] Parses correctly on systemd 246 through current, both JSON and legacy paths
- [ ] Failed-unit view is default and accurate
- [ ] All actions succeed and produce audit records
- [ ] Self-lockout guard triggers on network/SSH units
- [ ] Sudo password prompt detected and surfaced, never hung on
- [ ] Alpine/OpenRC lists services without crashing; unknown init shows the empty state

---

## M3 — journald log browsing

**Duration:** 2 weeks.

### Scope
- Filter by unit, priority, time range, free-text
- Follow mode (live tail)
- Jump to a specific timestamp
- Export selection

### Commands
```sh
journalctl -o json --no-pager -n 200 --reverse
journalctl -o json -u <unit> -p <0-7> --since "<ts>" --until "<ts>"
journalctl -o json -f          # follow
```

`-o json` emits newline-delimited JSON — parse incrementally, never buffer the whole response.

### Mobile-specific design
- **Pagination is mandatory.** Never fetch unbounded logs; default 200 lines, infinite scroll via `--until` cursor.
- Follow mode uses a dedicated session, cancelled on screen exit — a leaked follow session drains battery and holds an SSH channel.
- Priority colour coding: emerg/alert/crit/err red, warning amber, notice/info default, debug muted.
- Long lines wrap, never horizontally scroll.

### Permission handling
If `journalReadable` is false (user not in `systemd-journal`), fall back to sudo and surface a one-time tip:
`sudo usermod -aG systemd-journal $USER` — grants sudo-free log reads.

### Exit criteria
- [ ] Incremental NDJSON parser handles partial reads and malformed lines
- [ ] Follow mode terminates cleanly on navigation away (verified: no leaked sessions)
- [ ] 10,000-line scroll stays above 55fps
- [ ] Works both with and without `systemd-journal` membership
- [ ] Time-range filter correct across timezone boundaries

---

## M4 — Audit log and read-only mode

**Duration:** 1.5 weeks. **Ship before any destructive capability is exposed.**

### Audit schema

```dart
class AuditRecord {
  final String id;              // uuid v7, time-sortable
  final DateTime timestampUtc;
  final String hostId;
  final String hostAlias;
  final String remoteUser;
  final String command;         // exact string sent
  final RiskLevel risk;
  final bool usedSudo;
  final int? exitCode;
  final int durationMs;
  final String? errorSummary;   // never full stderr — may contain secrets
  final String appVersion;
}
```

### Guarantees
- Written **before** execution with `exitCode = null`, reconciled after. A record with a permanently null exit code indicates an interrupted operation — surfaced in the UI.
- Append-only. No update path except exit-code reconciliation. No delete except full purge.
- Optional hash chain: `sha256(prev_hash ‖ canonical_record)` for tamper evidence.
- Export as JSON and CSV.
- Retention configurable; default unlimited, with purge requiring biometric confirmation.

### Read-only mode
Enforced at the dispatch layer, not in the UI:

```dart
Future<T> execute<T>(Probe<T> probe, Host host) async {
  if (host.readOnly && probe.risk != RiskLevel.read) {
    throw ReadOnlyViolation(probe);
  }
  ...
}
```

UI hides mutating controls, but the dispatcher is the actual boundary. A UI bug must not be able to bypass it.

### Exit criteria
- [ ] Property test: no `mutate`/`destructive` probe executes on a read-only host, across all probes
- [ ] Every executed probe yields exactly one audit record (verified by counting test)
- [ ] Audit survives process kill mid-operation; orphan records surfaced
- [ ] Export round-trips correctly
- [ ] Secret-pattern scan over audit contents finds nothing

---

## M5 — Port forwarding and open-in-browser

**Duration:** 1.5 weeks.

### Scope
- Local port forward: `localhost:ephemeral → remote:port`
- Named presets: Cockpit 9090, Portainer 9443, Grafana 3000, custom
- Open forwarded URL in the device browser
- Active-tunnel list with teardown

### Design
- Bind to `127.0.0.1` only, on an ephemeral port. Never `0.0.0.0` — that would expose the tunnel to the local network.
- One SSH channel per tunnel; tear down on app background after a configurable grace period.
- Persistent notification while a tunnel is active (Android foreground service requirement).
- Warn when the target service is plain HTTP.

### Exit criteria
- [ ] Cockpit reachable through a tunnel end-to-end
- [ ] Tunnels bind to loopback only (verified by netstat assertion in test)
- [ ] All tunnels torn down on app termination — no orphaned channels
- [ ] Android foreground service notification correct and dismissible only by teardown

---

## M6 — Packages, firewall, disk triage

**Duration:** 3 weeks.

### 6a. Package management

| Manager | List updates | Security only |
|---|---|---|
| apt | `apt-get -s upgrade` | `apt-get -s upgrade -o Dir::Etc::SourceList=/etc/apt/security.sources.list` |
| dnf | `dnf check-update --refresh` (exit 100 = updates) | `dnf updateinfo list security` |
| zypper | `zypper -q lu` | `zypper lp --category security` |
| apk | `apk version -l '<'` | n/a |
| pacman | `checkupdates` (or `pacman -Qu`) | n/a |
| yum | `yum check-update` (older EL fallback) | `yum updateinfo list security` |

Apply is `destructive` risk — always requires confirmation, always shows the full package list first. Never auto-apply. Detect and surface `needs-restarting` / `/var/run/reboot-required`.

### 6b. Firewall

| Backend | Read | Notes |
|---|---|---|
| firewalld | `firewall-cmd --list-all --zone=<z>` | Zone-aware |
| ufw | `ufw status verbose` | Text parse |
| nftables | `nft -j list ruleset` | JSON native |
| iptables | `iptables-save` | Read-only in v1 |

**Rule changes are `destructive`** with a mandatory self-lockout guard: any rule affecting the SSH port must warn that it can permanently sever access. Offer a timed auto-revert (apply, wait 60s for confirmation, else roll back) — the standard safe pattern for remote firewall edits.

### 6c. Disk triage
The 2am workflow:
1. `df -PT` → find full filesystems
2. `du -x -d1 <mount> | sort -rh | head -20` → drill into the largest directories
3. Common offenders surfaced directly: `journalctl --disk-usage`, `/var/log`, `/var/cache`, Docker overlay
4. Suggested reclaims with size estimates: `journalctl --vacuum-size=`, package cache clean

Deletion is never automatic. The app shows the command; the user confirms.

### Exit criteria
- [ ] Package listing correct on all matrix distros
- [ ] Firewall auto-revert verified by killing confirmation and observing rollback
- [ ] SSH-port rule change triggers lockout guard
- [ ] `du` on a large filesystem does not block the UI or time out prematurely

---

## M7 — LLM assist

**Duration:** 2.5 weeks. **Last, deliberately.**

### Providers
| Provider | Config | Air-gap |
|---|---|---|
| None | Default | ✅ |
| Ollama | User-supplied base URL on LAN | ✅ |
| OpenAI-compatible | BYO key + base URL | ❌ |

No proxy service. No bundled key. The app never talks to a Tursina-operated endpoint.

### Capabilities
1. **Explain a failed unit** — input: `systemctl show` + last 50 journal lines. Output: plain-language cause and suggested next step.
2. **Explain disk usage** — input: `df` + `du` output. Output: what is consuming space and what is conventionally safe to remove.
3. **Intent → command** — natural language in, a *proposed* command into the command field. Never executed.
4. **Summarise logs** — long journal selection in, short summary out.

### Hard constraints
- **The model never executes anything.** It populates a field; the user confirms. Enforced structurally: the LLM module has no reference to the execution dispatcher.
- Proposed commands are risk-classified before display, and a `destructive` proposal carries a prominent warning.
- Model output is never parsed as a command to auto-run, in any code path.

### On-device redaction (mandatory before any non-local provider)
Redact before sending, restore for display:

| Pattern | Replacement |
|---|---|
| Hostnames from inventory | `<HOST_1>` |
| IPv4/IPv6 literals | `<IP_1>` |
| Email addresses | `<EMAIL_1>` |
| MAC addresses | `<MAC_1>` |
| Key-shaped strings (base64 ≥40 chars) | `<REDACTED>` |
| `password=`, `token=`, `secret=`, `Bearer ` values | `<REDACTED>` |
| Usernames from inventory | `<USER_1>` |

Redaction map is per-request and in-memory only. A **preview screen** shows the user exactly what will be transmitted, before the first cloud request per session.

### Exit criteria
- [ ] Zero network egress to any non-user-configured endpoint (verified by traffic capture)
- [ ] Redaction test suite covers all patterns, including adversarial inputs
- [ ] Structural proof that LLM output cannot reach the dispatcher (architecture test)
- [ ] Ollama path fully functional with no internet connectivity
- [ ] Provider defaults to None on fresh install

---

## M4.5 — Containers

**Duration:** 2.5 weeks. **Priority: high — this is what homelab users compare you against.**

### Scope
Docker and Podman. Auto-detect via `command -v docker podman` in HostFacts.

- Container list: name, image, state, uptime, ports, health
- Detail: env (redacted), mounts, networks, resource usage
- Actions: start, stop, restart, remove
- Logs: `docker logs --tail N --timestamps`
- Compose stack grouping via the `com.docker.compose.project` label
- Image list with disk usage; prune with confirmation

### Commands
```sh
docker ps -a --format '{{json .}}'          # NDJSON
docker inspect <id>                          # JSON
docker stats --no-stream --format '{{json .}}'
podman ps -a --format json                   # native JSON array
```

Podman's JSON differs from Docker's — separate parsers, shared model. Rootless Podman needs no sudo; Docker usually does unless the user is in the `docker` group.

### Risk
| Action | Risk |
|---|---|
| ps, inspect, logs, stats | `read` |
| start, restart | `mutate` |
| stop | `mutate` |
| remove, prune | `destructive` |

**Guard:** removing a container whose name matches the app's own tunnel or a reverse proxy fronting SSH triggers the self-lockout warning.

### Exit criteria
- [ ] Docker and Podman both parse correctly, including rootless Podman
- [ ] Compose stacks group correctly
- [ ] Env var display redacts secret-shaped values
- [ ] Prune shows reclaimable size before confirming

---

## M4.6 — SFTP file browser

**Duration:** 2 weeks. Parity feature — SysAdmin already ships this.

### Scope
- Browse, with permissions, owner, size, mtime
- Download to device, upload from device
- Rename, delete, chmod, mkdir
- **View and edit text files in-app** — the common real need is fixing a config
- **Unified diff before save** — buffer vs `.bak` (or vs the download if `.bak` was just created)
- Hidden-file toggle

### Design notes
- `dartssh2` provides SFTP; no extra dependency
- Streamed transfers with progress and cancel; never buffer a whole file in memory
- Editing: download to a temp file, edit, upload, **back up the original as `.bak` first**
- Binary detection — refuse to open in the text editor
- Path traversal outside the user's permitted scope fails gracefully with the server's error, not a crash

### Risk
Browse and download are `read`. Upload, rename, chmod, mkdir are `mutate`. Delete is `destructive`. Editing anything under `/etc/ssh/` or `authorized_keys` triggers the self-lockout warning.

### Exit criteria
- [ ] 1GB transfer completes with accurate progress and working cancel
- [ ] Edit-save-verify round trip on a config file, with `.bak` created
- [ ] Binary files refuse to open in the editor
- [ ] Permission-denied surfaces the server message, no crash
- [ ] Diff shown before save; save aborted if the user dismisses

---

## M4.7 — Operator velocity, incident

**Duration:** 2 weeks. **Priority: high — this is public v1.0, not M13 polish.**

M1.5 made the inventory fast. This milestone makes an incident finishable from a phone without five hops.

### Scope

**Incident sheet.** Attention chips on the hosts list and dashboard open a sheet: broken objects, last 20 relevant lines, related entity from cache, two actions (Explain if M7 exists; otherwise the most likely mutate). One tap from the list.

**Correlation.** Port → PID → unit/container. Failed unit → journal pre-filtered. Restarting container → logs + stack. Cache miss: "not in cache — look up" (`read` probe), never a blocking spinner on the sheet.

**In-host search.** Units, containers, snippet names, recent paths, pins. Local over cache.

**Snippets.** User templates with `{{unit}}`, `{{path}}`, `{{port}}`, `{{host}}`. Each snippet is a Probe: risk-classified, never auto-run, never fleet-applied, one audit record per expansion. Starters shipped (status, listen-on-port, `df -PT`, vacuum-journal proposed). JSON import/export in the backup.

**Diagnostic pack.** Copy/share redacted HostFacts + attention + failed units + last 50 journal lines + `df -PT`. Same redaction table as M7. No keys.

**Reversible mutate.** Disable → undo re-enable; stop (non-lockout) → undo start; 8s snackbar. Undo is a Probe and is audited. No undo on destructive.

**OS shortcuts.** Android App Shortcuts / iOS Shortcuts: last host, incident, last tunnel. Deep links `kelola://host/<id>/unit/<name>` and `.../incident`.

**Widget.** Optional, off by default. Worst host + failed count from last refresh, stale age visible. Tap → incident. No background polling beyond OS widget update limits. Not monitoring.

**Haptics.** Biometric success; destructive hostname match.

**Keep-awake.** Log follow, transfer, tunnel, terminal (extends M1.5).

### Exit criteria
- [ ] From hosts list, a failed-unit chip opens the incident sheet in one tap; restart is reachable without visiting the full unit list
- [ ] Property test: snippets cannot call the dispatcher except through `execute(Probe)`
- [ ] Property test: no snippet is invocable from fleet mode
- [ ] Diagnostic pack redaction matches the M7 suite; keys never present
- [ ] Undo of disable produces a second audit record and restores `enabled`
- [ ] Widget does not start SSH by itself (verified: no sessions while the app is force-stopped)
- [ ] Deep link to a missing host shows a clear miss, not a crash
- [ ] Correlation cache-miss does not block the incident sheet

---

## M9 — Terminal escape hatch

**Duration:** 2 weeks.

Deliberately not the primary surface — the escape hatch for the 5% the structured UI doesn't cover.

### Scope
- PTY session with correct window sizing
- ANSI colour and cursor handling
- Mobile keyboard accessory row: Tab, Esc, Ctrl, arrows, `|`, `/`, `-`, `~`
- Scrollback with selection and copy
- Paste from clipboard
- Multiple concurrent sessions per host

### Design notes
- `xterm.dart` or equivalent for terminal emulation
- Resize on keyboard show/hide; a wrong `SIGWINCH` breaks `vim` and `top`
- **Terminal commands are audited too** — record session start, end, and duration. Recording full keystrokes is out of scope and a privacy hazard; log the session boundary, not its contents.
- Bluetooth keyboard support

### Exit criteria
- [ ] `vim`, `top`, and `less` all render and respond correctly
- [ ] Keyboard show/hide resizes without corrupting the display
- [ ] Session start/end audited
- [ ] Backgrounding the app does not kill an active session prematurely

---

## M10 — Live metrics, processes, network

**Duration:** 2.5 weeks.

### 10a. Live metrics
Polling loop with a ring buffer, sparklines over 5m / 1h / 24h.

```sh
cat /proc/stat /proc/meminfo /proc/loadavg /proc/net/dev
```

Batch into one exec per tick. Default interval 5s foreground, paused in background. Compute CPU percentage from successive `/proc/stat` deltas — never `top`, which is slow and locale-dependent.

### 10b. Processes
```sh
ps -eo pid,ppid,user,pcpu,pmem,rss,stat,etime,comm,args --sort=-pcpu
```
Sort by CPU, memory, or name. Search. Detail view. `kill` (TERM) is `mutate`; `kill -9` and `renice` are `destructive`. Killing PID 1 or `sshd` is blocked outright.

### 10c. Network
```sh
ip -j addr; ip -j route          # JSON native
ss -tulpn                        # listening ports
```
Interfaces with addresses and state, routing table, listening ports with owning process. Read-only in v1 — network mutation from a phone is how you lose the host.

### Exit criteria
- [ ] Metrics poll without measurable battery drain over 30 minutes
- [ ] Polling stops on background, resumes on foreground
- [ ] CPU percentage matches `top` within 2%
- [ ] Kill guard blocks PID 1 and `sshd`
- [ ] `ip -j` fallback to text parsing on older iproute2

---

## M11 — Cron and users

**Duration:** 1.5 weeks. Parity — SysAdmin ships both.

### Cron
- User crontabs (`crontab -l -u`) and system (`/etc/crontab`, `/etc/cron.d/`)
- systemd timers: `systemctl list-timers --output=json`
- Human-readable schedule translation ("every day at 3:15 AM")
- Create, edit, delete with syntax validation before write

### Users
- List from `/etc/passwd` and `/etc/group`, filtered to real users
- Detail: shell, home, groups, last login (`lastlog`), lock status
- Create, modify groups, lock/unlock, set shell
- **Never display or set passwords.** Password changes are out of scope — the app is key-only by principle and shouldn't handle passwords for others either.

### Risk
All user mutations are `destructive`. Removing your own user, changing your own shell to `nologin`, or locking your own account triggers the self-lockout guard.

### Exit criteria
- [ ] Cron syntax validated before write; invalid entries rejected with a clear message
- [ ] systemd timers listed alongside cron
- [ ] Self-account modification guarded
- [ ] No password field exists anywhere in the UI

---

## M12 — Fleet view

**Duration:** 2.5 weeks. **The real differentiator — neither competitor has this.**

### Scope
One check, many hosts, one screen.

- Health grid: every host with reachability, load, disk, failed units, pending updates
- Parallel execution with a bounded concurrency limit
- Sort by severity — the unhealthy ones surface first
- Saved fleet checks: pick a probe, run it across a host group
- Group tagging: prod, staging, homelab, client-A

### Design notes
- Concurrency cap of 5 hosts; mobile radios and SSH handshakes are the bottleneck
- Per-host timeout of 10s; a slow host must not block the grid
- Partial results render as they arrive — never wait for all
- Cache last-known state with an explicit staleness age; offline shows the cache clearly marked
- Only `read` probes run in fleet mode. Bulk mutation across a fleet from a phone is out of scope, deliberately, and that limit should be stated in the docs.

### Exit criteria
- [ ] 20 hosts refresh in under 15s
- [ ] One unreachable host does not block the other 19
- [ ] Results render progressively
- [ ] No `mutate` probe is reachable from fleet mode (property test)
- [ ] Stale cache is visibly labelled with its age

---

## M13 — Polish and release readiness

**Duration:** 3 weeks.

- **Onboarding**: three screens max, ending at a working connection. The first-run path must reach a real host, not a settings tour. **Import ssh_config** is offered on the add-host screen, not buried in settings.
- **Empty states**: every list has one that invites the next action, including snippets and search-no-hits.
- **Backup/restore**: export host inventory and settings, encrypted, with a passphrase. Keys are non-exportable by design — the restore flow must explain that re-enrollment is required, and make it painless.
- **i18n**: English and Bahasa Indonesia. Extract all strings; no hardcoded text.
- **Accessibility**: screen reader labels on every control, 4.5:1 contrast minimum, 48dp touch targets, respects reduced motion.
- **Tablet layout**: two-pane master-detail above 600dp. Hardware keyboard: `Ctrl+K` / `Cmd+K` opens global search.
- **Docs site**: setup, enrollment, bastion, tunnels, security model, threat model.
- **Sustainability**: Ko-fi and GitHub Sponsors. The app stays fully free — no paywalled features, since that's the studio's premise.

### Exit criteria
- [ ] Fresh install to first successful connection in under 3 minutes, unassisted
- [ ] Accessibility scanner passes with zero critical findings
- [ ] Both locales complete, no missing keys
- [ ] Backup/restore round trip verified, including the key re-enrollment path
- [ ] Docs cover every feature shipped

---

## Cross-cutting: CI distro matrix

Every parser milestone runs against real containers running `sshd`:

| Image | Represents |
|---|---|
| `ubuntu:24.04` | apt, systemd current, ufw |
| `debian:12` | apt, systemd stable |
| `rockylinux:9` | dnf, firewalld, SELinux |
| `opensuse/leap:15` | zypper |
| `alpine:latest` | apk, OpenRC — **no systemd** |
| `archlinux:latest` | pacman, rolling systemd |

Alpine's inclusion is deliberate: it forces graceful degradation when systemd is absent, rather than a crash.

---

## M8 — Reaching hosts behind NAT

**Duration:** 3 weeks. **Prerequisite:** M1 connection layer stable.

### The constraint that shapes everything

**Both Android and iOS permit only one active VPN at a time.**

- Android: `VpnService` — a single app holds the TUN interface. Establishing yours tears down the user's corporate VPN.
- iOS: `NEPacketTunnelProvider` — same single-tunnel limit. Per-app VPN is the exception, and it requires MDM enrolment.

So implementing a system-level VPN **disqualifies the app for anyone on a corporate VPN** — which is a stated requirement. A naive "add WireGuard to the app" approach breaks the enterprise use case to serve the homelab one.

### Tiered approach

#### T0 — Bastion via ProxyJump (already built, ships with M1)

If the user has any one publicly-reachable host, `ProxyJump` reaches everything behind it. This is already in M1 and solves NAT completely for anyone with a VPS, a router with a forwarded port, or a cloud jump box.

**Lead with this in documentation.** It is free, standard, requires nothing new, and covers a large share of users. Many people asking "how do I reach my homelab" already have a VPS and don't realise a jump host is the answer.

#### T1 — Documentation for OS-level tunnels (ships with M1)

User installs Tailscale or WireGuard at the OS level themselves. The app inherits routing with zero code, because it uses the OS network stack. Document the setup for both.

Covers most of the remaining homelab users. Costs nothing to support.

#### T2 — Embedded userspace WireGuard (this milestone)

For users who want it to just work without a second app, and — critically — **without displacing a corporate VPN.**

**Design: userspace WireGuard with its own netstack.** Only the app's own SSH sockets traverse the tunnel. No `VpnService`, no `NEPacketTunnelProvider`, no OS VPN permission, no interface claim. Coexists with any system VPN because the OS never knows a tunnel exists.

```
dartssh2 SSHClient
   └─ SSHSocket (interface)
        ├─ dart:io Socket          ← direct / system VPN
        └─ WireGuardSocket (new)   ← userspace tunnel via FFI
```

`dartssh2` accepts a pluggable `SSHSocket`, which makes this substitution clean — implement the interface over the userspace netstack and nothing above it changes.

**Implementation:** FFI to `boringtun` (Rust) or `wireguard-go`. Both are userspace by design. Rust via `flutter_rust_bridge` is likely the lower-friction path and gives smaller binaries.

**Config import:**
- Paste a `wg-quick` config
- **Scan a WireGuard QR code** — the standard distribution format, and it reuses the QR scanner already built for key enrollment
- Per-host association: each host in the inventory optionally names a tunnel

**Explicitly out of scope:** acting as a general VPN, routing other apps' traffic, exit nodes, DNS interception.

#### T3 — Tailscale integration (deferred, likely never)

OAuth, embedded node, MagicDNS, DERP relay fallback. Large scope — Tailscale's NAT traversal is genuinely hard engineering, and an embedded node is a project in itself. Revisit only if T0–T2 demonstrably fail users.

### Exit criteria
- [ ] Userspace tunnel establishes with **no** OS VPN permission requested
- [ ] Corporate VPN remains active and unaffected while the app tunnel is up (verified on a real MDM-managed device)
- [ ] Handshake and rekey correct against a standard WireGuard peer
- [ ] `wg-quick` config and QR import both round-trip correctly
- [ ] Tunnel torn down on app termination; no battery drain when idle
- [ ] Private keys for tunnels stored in the same hardware-backed path as SSH keys where the platform permits
- [ ] Air-gapped operation unaffected — tunnel is optional and off by default

### Risks
| Risk | Mitigation |
|---|---|
| FFI binary size and build complexity | Evaluate `boringtun` size in a spike before committing |
| Userspace netstack performance on mobile | SSH is low-bandwidth; acceptable. Benchmark anyway. |
| Users expect full-device VPN | Document the scope clearly — this tunnels the app only, by design |
| WireGuard key handling weakens the security story | Same hardware-backed storage path, or explicitly documented if the platform forbids it |

---

## Sequencing rationale

M0 first because it can kill the project. M4 (audit + read-only) before any destructive capability ships. M1.5 ships with connection because resume, search, and attention-sort are how people re-enter the app. Containers and SFTP early because they are the features users compare you against. **M4.7 ships in public v1.0** — an incident that takes five hops is not a 2am product. The LLM lands late because it is the most visible feature and the least important; an assistant sitting on top of a broken parser is worse than no assistant.

### Recommended order

| Phase | Milestones | Outcome |
|---|---|---|
| **Foundation** | M0, M1, M1.5 | Connects, discovers, displays, resumes, searches inventory |
| **Core admin** | M2, M3, M4 | Services, logs, audit — shippable alpha |
| **Parity** | M4.5, M4.6, M4.7 | Containers, files, **incident/snippets/widget** — **public v1.0** |
| **Depth** | M5, M6, M9 | Tunnels, packages, firewall, terminal |
| **Insight** | M10, M11 | Metrics, processes, network, cron, users |
| **Differentiate** | M12, M8 | Fleet view, NAT traversal |
| **Assist** | M7 | LLM |
| **Ship** | M13 | Polish, i18n, docs, release |

### Timeline

Roughly **35 weeks of focused engineering**. At a sustainable solo pace alongside full-time work, plan for **8–10 months** to M13.

**v1.0 is Foundation + Core admin + Parity** — about 16 weeks, including operator velocity. Ship there, get users, and let their feedback reorder everything after it.

