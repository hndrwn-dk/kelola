import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/der_ecdsa.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';

/// Bridges a hardware-backed P-256 key into dartssh2 via SSHIdentity.custom.
///
/// dartssh2 3.3.1 already hashes-then-signs on the library side for software
/// keys; the challenge passed here is the raw SSH session blob. Android
/// `SHA256withECDSA` and iOS `ecdsaSignatureMessageX962SHA256` hash it once.
class HardwareSshIdentity {
  HardwareSshIdentity({
    required this.signer,
    required this.alias,
    required this.publicBlob,
    this.comment = 'kelola',
  });

  final HardwareSigner signer;
  final String alias;
  final Uint8List publicBlob;
  final String comment;

  factory HardwareSshIdentity.fromSpki({
    required HardwareSigner signer,
    required String alias,
    required Uint8List spki,
    String comment = 'kelola',
  }) {
    final q = OpensshEcdsaP256.pointFromSpki(spki);
    final blob = OpensshEcdsaP256.publicBlobFromPoint(q);
    return HardwareSshIdentity(
      signer: signer,
      alias: alias,
      publicBlob: blob,
      comment: comment,
    );
  }

  SSHIdentity toIdentity() {
    return SSHIdentity.custom(
      type: OpensshEcdsaP256.type,
      publicKey: SSHRawHostKey(publicBlob),
      comment: comment,
      shouldProbe: true,
      signer: (data) async {
        final der = await signer.sign(alias, data);
        final parsed = DerEcdsaSignature.parse(der);
        return SSHRawSignature(parsed.toSshSignature());
      },
    );
  }
}
