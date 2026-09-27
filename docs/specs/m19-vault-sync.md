# M19 — Encrypted vault sync

No Kelola server. The primitive is a passphrase-sealed blob plus a
transport the user already owns. Manual file export/import stays free.
LAN pairing and the host SFTP vault are Pro.

Full design: `docs/superpowers/specs/2026-09-27-m19-vault-sync-design.md`.

## Rules

- `vaultSchemaVersion` is independent of Drift. Refuse a newer blob
  rather than half-apply it. Unknown plaintext fields survive
  round-trip.
- Seal with Argon2id then AES-256-GCM. Never persist the passphrase.
- StrongBox material never enters the blob. Software keys and stored
  passwords are opt-in, default off, separate confirmation.
- Merge is last-write-wins on `id` + `updatedAt` with device-id
  tiebreak, plus tombstones. Show a diff sheet before apply.
- `VaultTransport`: file (free), LAN X25519 (Pro), SFTP
  `~/.kelola/vault.age` (Pro). Entitlement lives in Settings / the
  vault controller, never in `lib/domain/vault`.
- After import, offer enroll. Do not push a new public key silently.
