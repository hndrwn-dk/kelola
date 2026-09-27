# M23 — SSH user certificates

Free. Vault/Teleport shops issue a short-lived OpenSSH user
certificate for a public key. Kelola already has that key in
StrongBox. The cert is public material — paste it per host.

## Rules

- Support `ecdsa-sha2-nistp256-cert-v01@openssh.com` only, matching
  the on-device P-256 key.
- Refuse a cert whose inner public key is not Kelola's current key.
- Refuse a host cert (`type != 1`) and an expired cert.
- Do not verify the CA signature on the phone. sshd does that.
- Do not store a CA private key. StrongBox still signs.
- Empty field keeps today's authorized_keys identity.
- Vault packs the cert on the host record without bumping
  `vaultSchemaVersion`.
