import 'package:dartssh2/dartssh2.dart';

/// Modern algorithms only: no SHA-1 KEX, no CBC, no ssh-rsa.
///
/// aes256-ctr and hmac-sha2-256 are included because some WSL/Windows OpenSSH
/// configs disable AES-GCM and ChaCha20. They are not legacy.
class KelolaAlgorithms {
  static const ssh = SSHAlgorithms(
    kex: [
      SSHKexType.x25519Rfc,
      SSHKexType.x25519,
      SSHKexType.nistp256,
    ],
    cipher: [
      SSHCipherType.chacha20poly1305,
      SSHCipherType.aes256gcm,
      SSHCipherType.aes256ctr,
    ],
    hostkey: [
      SSHHostkeyType.ed25519,
      SSHHostkeyType.ecdsa256,
      SSHHostkeyType.rsaSha512,
      SSHHostkeyType.rsaSha256,
    ],
    mac: [
      SSHMacType.hmacSha256Etm,
      SSHMacType.hmacSha256,
    ],
  );
}
