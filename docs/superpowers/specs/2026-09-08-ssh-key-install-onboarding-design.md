# SSH key install onboarding

**Date:** 2026-09-08  
**Status:** approved  
**Scope:** Replace broken QR / copy-only enrollment with password-bootstrap install (closed testing) plus a always-available manual path. QR is removed.

## Problem

Installing Kelola’s public key requires SSH access that does not yet use that key. Today the only path is hand-copy from the app. The enrollment QR does not scan usefully (servers have no camera) and the copy misleads. Password bootstrap over SSH is a feature (dartssh2 supports it; Kelola is key-only today), not a config flip.

## Goals

1. Optional password-bootstrap flow that appends the phone’s public key safely, then verifies with a **new** key-only connection.
2. Manual path always available: full key line, install commands, fingerprint, Test connection.
3. Password never persisted or logged; discarded on every exit path.
4. Honest outcomes: appended vs already-present vs append-ok/verify-fail vs append-fail; three distinct pre-install failure modes.

## Non-goals

- Phone-to-phone QR transfer (removed entirely).
- `ssh-copy-id`.
- Silent fallback from failed key auth to password.
- Rewriting, sorting, or deduplicating other `authorized_keys` entries.
- Using the generic Files / SFTP editor for this write (`isSshLockoutPath` stays for that surface).

---

## Current baseline

| Area | Today |
|------|--------|
| Auth | Key-only via `SshSessionPool._open` (`identities` only) |
| Library | dartssh2 `onPasswordRequest` available, unused |
| Enrollment UI | QR + `KelolaCommand` with full `authorizedKeysLine`; Test connection |
| Copy | Complete line: `ecdsa-sha2-nistp256 <base64> kelola` |
| Host key | TOFU (`TofuScreen`) / mismatch (`HostKeyMismatchScreen`) already exist |
| Lockout | `authorized_keys` blocked in Files UI |

---

## UX overview

Replace `EnrollmentScreen` content (same route in the add-host chain).

**Lead with (always):**

1. One honest line: installing the key needs existing access (another SSH session, web console, or physical access). Never suggest messaging apps — integrity, not secrecy.
2. Monospace full public key + copy (complete line).
3. Ready-to-paste install command block + copy (manual path; see below).
4. Key fingerprint (`SHA256:…` from `OpensshEcdsaP256.fingerprintSha256`).
5. Primary path choice: **Install with password** | stay on manual + **Test connection**.

**QR:** removed. No replacement affordance.

Compose with Kelola design system (`RiskBand` / `ServiceRow` / `KelolaSheet` / `DestructiveConfirmSheet` as appropriate). Server strings → `KelolaType.mono`; human labels → display/body. No new accent colors; no FAB; bottom sheets use `KelolaSheet`.

---

## Flow — order is the security property

### STEP 1 — Host key before credentials

- Open a bootstrap SSH connection that authenticates with password **only after** host-key verification returns.
- Implementation constraint: dartssh2 calls `onVerifyHostKey` during handshake **before** userauth. Password must not be supplied until the user has trusted the host key (or the pin already matches).
- **Unknown key:** first-contact UI (existing TOFU / equivalent). User must accept before password is sent.
- **Pinned and changed:** hard stop via existing mismatch UI — **never** first-contact UI. Abort; discard password if already held (should not be held yet).
- Credentials are never sent before trust is recorded (pin write) or mismatch abort.

### STEP 2 — Password

- Explicit user choice: they tapped **Install with password** and entered a password.
- Never a silent fallback after failed key auth.
- Held only in memory for the bootstrap session lifetime.
- No keyboard-interactive multi-prompt beyond what is required to deliver that single password for `password` auth. Prefer `onPasswordRequest` only; do not enable a general keyboard-interactive scavenger hunt.

### STEP 3 — Show what will be written

- After password authentication has succeeded on the bootstrap session: show the full public key line + fingerprint.
- Primary action: **Install this key**. Decision point, not FYI — append has not run yet.
- Cancel / back → discard password, close bootstrap session, nothing written.

### STEP 4 — Append (dedicated enrollment op)

Remote script (approved), with substitutions validated first (see Substitution safety).

```bash
set -eu
AK="$HOME/.ssh/authorized_keys"
KEY_BODY='__KEY_BODY__'
LINE='__FULL_LINE__'
CREATED_SSH=0

# StrictModes cares about $HOME as well as ~/.ssh. Record only — never chmod $HOME.
HOME_MODE="$(ls -ld "$HOME" | awk '{print $1}')"

if [ ! -d "$HOME/.ssh" ]; then
  mkdir -m 700 "$HOME/.ssh"
  CREATED_SSH=1
fi

if [ ! -f "$AK" ]; then
  umask 077
  : >> "$AK"
  chmod 600 "$AK"
fi

if [ "$CREATED_SSH" -eq 1 ]; then
  if command -v restorecon >/dev/null 2>&1; then
    restorecon -R "$HOME/.ssh" 2>/dev/null || true
  fi
fi

if [ -s "$AK" ]; then
  last="$(tail -c 1 "$AK" | wc -l)"
  if [ "$last" -eq 0 ]; then
    printf '\n' >> "$AK"
  fi
fi

if grep -F -- "$KEY_BODY" "$AK" >/dev/null 2>&1; then
  printf 'HOME_MODE=%s\nCREATED_SSH=%s\n' "$HOME_MODE" "$CREATED_SSH"
  exit 3
fi

printf '%s\n' "$LINE" >> "$AK"
printf 'HOME_MODE=%s\nCREATED_SSH=%s\n' "$HOME_MODE" "$CREATED_SSH"
exit 0
```

| Exit | Meaning |
|------|---------|
| `0` | Appended this run |
| `3` | Key body already present in the file (may be commented or option-restricted — see STEP 5/6) |
| other | Append failed |

Stdout on exit 0/3 includes `HOME_MODE=…` and `CREATED_SSH=0|1` so the client can explain verify failures without a second privileged read.

**Rules encoded above**

- Append only (`>>` / `printf … >>`); never truncate with `>`.
- Idempotent match on **key body** only.
- Trailing newline fixed before append when file non-empty and does not end in `\n`.
- No rewrite/sort/dedup of other lines.
- Permissions only when creating (`mkdir -m 700`, `chmod 600` on new file); existing modes untouched.
- SELinux: `restorecon` only when **we created** `~/.ssh`; never fail install if `restorecon` missing.
- StrictModes: record `$HOME` mode; **never** `chmod "$HOME"`.

Transport: build the script in Dart only after validation; send as a single remote exec. Invoke **`sh`**, never `bash` (Alpine / busybox ash — in Tested-on). Preferred form: pipe or stdin to `sh -s` (or `sh -c` with a base64-decoded script body). The script must remain POSIX-clean (`printf`, `tail -c`, `wc`, `grep -F`, `command -v`, `awk`). No bashisms.

Dedicated op: not `SftpWrite` / file editor. Enrollment module owns this exec.

### STEP 5 — Verify with a new connection

- Close / do not reuse the bootstrap client for proof.
- Open a **fresh** `SSHClient` with **key identity only** (no `onPasswordRequest`).
- Assert at session-pool / open API level that bootstrap sessions are not returned from the pool for this verify (e.g. disconnect host id after append, or open with an explicit non-pooled path used only here).
- Run a minimal probe (e.g. `HostFactsProbe` or equivalent auth proof).

### STEP 6 — Report honestly

| Situation | User-facing outcome | Audit |
|-----------|---------------------|--------|
| Exit 0 + verify OK | Installed and verified | Append recorded as added |
| Exit 3 + verify OK | Key was already present; connection works | Must **not** claim we added a key |
| Exit 0 + verify fail | File **was** modified **and** key did not authenticate. Show the exact line we appended and a removal hint (manual; do **not** auto-remove). Candidate causes, as applicable: (a) `$HOME` group/world-writable (StrictModes) when `HOME_MODE` indicates it; (b) SELinux context if we created `~/.ssh`; (c) `sshd` may read a different `AuthorizedKeysFile`. | Append yes; verify fail |
| Exit 3 + verify fail | Key body is present but did not authenticate — check for options (`command=`, `from=`) or a commented line; also list StrictModes / `AuthorizedKeysFile` as candidates when relevant | Already present; verify fail |
| Append failed (other exit / exec error) | Report failure; never claim success; file state unknown/unverified | Mode attempted; failure |

Never report success on unverified write.

**Append-ok / verify-fail stray key:** Always show the exact `LINE` that was appended and a removal hint such as editing `~/.ssh/authorized_keys` to delete that line. Do not offer automatic removal — that would be another privileged write after something already failed.

**Verify-fail cause list (cheap, ordered):**

1. If `HOME_MODE` shows group or world write → say `$HOME` is group/world-writable; sshd StrictModes will refuse key auth; Kelola will not chmod `$HOME`.
2. If `CREATED_SSH=1` → mention SELinux context (`restorecon -R ~/.ssh`) as likely on RHEL-family.
3. Always mention: sshd may use a different `AuthorizedKeysFile` (e.g. `/etc/ssh/authorized_keys/%u`); we cannot read `sshd_config` as this user.
4. If exit 3 → options / commented line on the matching body.

---

## Manual path (always available)

Shown on the same screen (and as fall-through after password failures):

1. Honest upfront line (existing access required).
2. Full public key monospace + copy (complete line).
3. Ready-to-paste install commands + copy (not `ssh-copy-id`):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo '<pubkey>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

   (`<pubkey>` = full authorized_keys line.) Manual paste path does not include `restorecon`; document in the SELinux note near fingerprint / verify failure copy that RHEL-family hosts may need `restorecon -R ~/.ssh` if the directory was created outside Kelola’s bootstrap.

4. Fingerprint alongside for out-of-band compare.
5. **Test connection** — real key-only probe (existing behavior, keep). Onboarding must not “succeed” silently without it.

Never suggest sending the key through a messaging app.

---

## Password auth failure modes (three, not one)

If password install is attempted and fails **before** append:

| Mode | Detection (sketch) | UI | Retry |
|------|--------------------|----|--------|
| 1. Authentication rejected | Auth failed after host key OK; server offered/attempted password | Credential error; offer retry + manual | Yes |
| 2. Password auth disabled | Server auth methods exclude password (and keyboard-interactive if we only use password) | Not retryable; say PasswordAuthentication is off / password not offered; manual only | **No** retry affordance |
| 3. Connection failed before auth | Timeout, refused, DNS, port, socket errors | Connectivity error — **not** a password error | Fix network / host; not credential retry |

On any of these: password discarded; nothing written; fall through to manual path.

Distinguishing (1) vs (2) must use server-advertised auth methods / dartssh2 auth exhaustion signals, not guesswork from a generic “auth failed” string alone when methods are visible.

---

## Password disposal (guarantee)

- Store password only in a short-lived holder cleared in a `finally`-equivalent on: success, append failure, verify failure, cancel, route dispose, app background (WidgetsBinding observer), connection drop.
- **Never pass** the password string into: `recordAudit`, Drift companions, SharedPreferences / settings, diagnostic packs, LLM payloads, crash report custom keys, or SnackBar/error text.
- Redaction (`redactText`) remains defense-in-depth for accidental `password=` patterns; it is **not** the disposal mechanism.
- UI may show **password discarded** only after the clear has run.

---

## Audit

Plain English, no secrets:

- Success append: e.g. `Added Kelola public key to <alias>` with command/meta noting **append**.
- Already present + verified: e.g. `Kelola public key already on <alias>` — must not say “added”.
- Failures: record mode attempted (password install / verify / append) and outcome; never password material.

---

## Substitution safety

Before building the remote script:

- Reject `KEY_BODY` or comment if it contains: `'`, `"`, `\`, newline, or any whitespace.
- Comment remains the literal constant `kelola` unless validation still runs on whatever comment is used.
- Unit-test: valid base64 body passes; each forbidden character fails before any remote exec.

---

## Architecture (sketch)

```
EnrollmentScreen
  ├─ ManualKeyInstallPanel (key, commands, fingerprint, Test)
  └─ PasswordInstallFlow (explicit)
        ├─ Step1 host key (reuse TOFU / mismatch)
        ├─ Step2 password field (memory holder)
        ├─ Step3 confirm Install this key
        ├─ KeyInstallAppendProbe / enrollment exec (STEP 4)
        ├─ disconnect + fresh key-only open (STEP 5)
        └─ outcome UI + audit (STEP 6)
```

- Extend session open for **bootstrap**: password handler only when explicitly requested; never for normal pool opens.
- Verify path: key-only; assert no password handler; not the same client instance as bootstrap.

---

## Tests

### Append safety (script / builder unit tests)

- File with 3 existing keys → all 3 remain + ours (exit 0).
- No trailing newline → last existing key and ours both valid.
- Install twice → exactly one entry (second exit 3).
- Missing `~/.ssh` → created 700; existing stricter mode untouched.
- `CREATED_SSH=1` path includes `restorecon` guard; absence of `restorecon` still exit 0/3 as appropriate.
- Forbidden characters in body/comment rejected in Dart before script build.
- Script runs under a POSIX `sh` (no bash); test invokes `sh` (or busybox ash) and asserts exit codes / file results.
- Stdout reports `HOME_MODE` and `CREATED_SSH`; never chmods `$HOME`.

### Flow

- Credentials never sent before host-key trust recorded (ordering test / fake SSH).
- Changed host key → mismatch UI, not TOFU; no password send.
- Verification uses a new connection (session-level assert).
- Append failure vs verify failure → distinct messages; verify failure never “success”.
- Exit 3 + verify fail → “present but did not authenticate” + options/comment guidance.
- Exit 0 + verify fail → shows appended line + removal hint; mentions StrictModes when home is group/world-writable; SELinux when we created `~/.ssh`; always mentions `AuthorizedKeysFile` as a candidate.

### Password

- Unreachable after every exit path including cancel and background.
- Absent from audit, Drift, prefs, LLM payload fixtures.

### Failure modes

- Each of the three modes → distinct message and next action.
- Password-disabled → no retry affordance.
- Pre-auth connection failure never renders as credential error.

---

## Play / closed testing

Ship the full flow in closed testing. Manual path remains the fallback for hardened hosts with `PasswordAuthentication no`.

---

## Open implementation notes (not product choices)

- Exact dartssh2 signals for “password not offered” vs “rejected” — wire to the three failure modes during implementation; product meanings are fixed above.
- Script transport: **`sh -s`** (or equivalent POSIX `sh`), never `bash`. Encoding of the script body (stdin vs base64-into-`sh -c`) must preserve script semantics.

## Out of scope follow-ups

- Broader SFTP unlock of `authorized_keys` for the Files UI.
- Multi-factor / forced password change during bootstrap (`onChangePasswordRequest`) — abort with clear message; do not invent a change-password UX in v1.
