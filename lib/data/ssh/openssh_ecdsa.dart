import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kelola/data/ssh/ssh_wire.dart';

class OpensshEcdsaP256 {
  static const type = 'ecdsa-sha2-nistp256';
  static const curve = 'nistp256';

  /// Uncompressed EC point is 0x04 || X || Y (65 bytes).
  static Uint8List publicBlobFromPoint(Uint8List q) {
    if (q.length != 65 || q[0] != 0x04) {
      throw FormatException(
        'expected uncompressed P-256 point (65 bytes), got ${q.length}',
      );
    }
    final w = SshWireWriter()
      ..writeUtf8(type)
      ..writeUtf8(curve)
      ..writeString(q);
    return w.takeBytes();
  }

  /// SubjectPublicKeyInfo (X.509) from Android/iOS -> uncompressed point.
  static Uint8List pointFromSpki(Uint8List spki) {
    if (spki.length >= 65) {
      final tail = Uint8List.sublistView(spki, spki.length - 65);
      if (tail[0] == 0x04) {
        return Uint8List.fromList(tail);
      }
    }
    for (var i = spki.length - 65; i >= 0; i--) {
      if (spki[i] == 0x04) {
        return Uint8List.fromList(spki.sublist(i, i + 65));
      }
    }
    throw const FormatException('no uncompressed P-256 point in SPKI');
  }

  static String authorizedKeysLine(Uint8List blob, {String comment = 'kelola'}) {
    return '$type ${base64Encode(blob)} $comment';
  }

  static String enrollmentOneLiner(Uint8List blob, {String comment = 'kelola'}) {
    final line = authorizedKeysLine(blob, comment: comment);
    return "echo '$line' >> ~/.ssh/authorized_keys";
  }

  /// OpenSSH SHA256 fingerprint, unpadded.
  static String fingerprintSha256(Uint8List blob) {
    final digest = sha256.convert(blob);
    var b64 = base64Encode(digest.bytes);
    while (b64.endsWith('=')) {
      b64 = b64.substring(0, b64.length - 1);
    }
    return 'SHA256:$b64';
  }
}
