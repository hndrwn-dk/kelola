# M0 — Hardware key spike: go / no-go

Date: 2026-08-25
Status: **Conditional GO** — library path is proven in source; physical-device
exit criteria are still open.

## Investigation

1. **dartssh2 3.3.1** exposes `SSHIdentity.custom` with an async `signer`
   callback, RFC 4252 public-key probing (`shouldProbe: true`), and
   `SSHRawHostKey` / `SSHRawSignature`. This is the hook M0 required.
   A local patch or libssh2 FFI is **not** needed.
2. The library passes the **raw SSH challenge blob** into `sign()`. Software
   ECDSA in dartssh2 hashes with SHA-256 internally. Android
   `SHA256withECDSA` and iOS `ecdsaSignatureMessageX962SHA256` do the same
   one hash. Do **not** use `NONEwithECDSA`.
3. Platform keys still emit **ASN.1 DER**. Conversion to SSH `mpint r || mpint s`
   lives in `lib/data/ssh/der_ecdsa.dart` and is covered by unit tests.

## Scaffold in this repo

| Piece | Location |
|---|---|
| Platform contract | `lib/data/keystore/hardware_signer.dart` |
| Method channel | `lib/data/keystore/method_channel_hardware_signer.dart` |
| Android StrongBox → TEE fallback | `android/.../HardwareSignerPlugin.kt` |
| iOS Secure Enclave (simulator: software) | `ios/Runner/HardwareSignerPlugin.swift` |
| dartssh2 identity | `lib/data/ssh/hardware_identity.dart` |

## Remaining exit criteria (physical devices)

- [ ] StrongBox key + attestation on a real Android device
- [ ] Secure Enclave key on a real iPhone
- [ ] `ssh` auth against OpenSSH 8.x and 9.x
- [ ] Biometric prompt on each sign
- [ ] Export of the private key fails

Until those boxes are ticked, the UI must label the backend
(`strongbox` / `secureEnclave` / `tee` / `software`). A software backend is a
**weaker product**, not a silent fallback.

## Decision

**GO on the library and converter.** Proceed with M1 on top of `SSHIdentity.custom`.
Do not start a libssh2 FFI track unless a physical-device spike fails auth after
the DER converter is verified.
