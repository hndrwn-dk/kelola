import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';

void main() {
  test('encodes an uncompressed P-256 point as OpenSSH authorized_keys', () {
    final q = Uint8List(65)..[0] = 0x04;
    for (var i = 1; i < 65; i++) {
      q[i] = i;
    }
    final blob = OpensshEcdsaP256.publicBlobFromPoint(q);
    final line = OpensshEcdsaP256.authorizedKeysLine(blob, comment: 'kelola');
    expect(line.startsWith('ecdsa-sha2-nistp256 '), isTrue);
    expect(line.endsWith(' kelola'), isTrue);
    expect(OpensshEcdsaP256.fingerprintSha256(blob).startsWith('SHA256:'), isTrue);

    final fromSpki = OpensshEcdsaP256.pointFromSpki(q);
    expect(fromSpki, q);
  });
}
