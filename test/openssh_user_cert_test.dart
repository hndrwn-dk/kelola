import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/ssh_wire.dart';
import 'package:kelola/domain/ssh/openssh_user_cert.dart';

Uint8List _point() => Uint8List.fromList([0x04, ...List<int>.filled(64, 3)]);

Uint8List _certBlob({
  int type = kOpenSshCertTypeUser,
  int validAfter = 0,
  int validBefore = 0,
  Uint8List? point,
}) {
  final q = point ?? _point();
  final principals = SshWireWriter()..writeUtf8('ops');
  final body = SshWireWriter()
    ..writeUtf8(kOpenSshEcdsaUserCertType)
    ..writeString(Uint8List.fromList([1, 2, 3]))
    ..writeUtf8(OpensshEcdsaP256.curve)
    ..writeString(q)
    ..writeUint64(9)
    ..writeUint32(type)
    ..writeUtf8('kelola')
    ..writeString(principals.takeBytes())
    ..writeUint64(validAfter)
    ..writeUint64(validBefore)
    ..writeString(Uint8List(0))
    ..writeString(Uint8List(0))
    ..writeString(Uint8List(0))
    ..writeString(Uint8List.fromList([4]))
    ..writeString(Uint8List.fromList([5]));
  return body.takeBytes();
}

void main() {
  test('parses a user cert and matches the inner public key', () {
    final blob = _certBlob();
    final line = '$kOpenSshEcdsaUserCertType ${base64Encode(blob)} vault';
    final cert = parseOpenSshUserCert(line);
    expect(cert.serial, 9);
    expect(cert.keyId, 'kelola');
    expect(cert.principals, ['ops']);
    expect(cert.matchesPublicBlob(OpensshEcdsaP256.publicBlobFromPoint(_point())), isTrue);
    expect(cert.isValidAt(DateTime.utc(2026, 9, 27)), isTrue);
  });

  test('refuses host certs, expiry, and a different public key', () {
    expect(
      () => parseOpenSshUserCert(base64Encode(_certBlob(type: 2))),
      throwsA(isA<FormatException>()),
    );
    final expired = parseOpenSshUserCert(
      base64Encode(_certBlob(validBefore: 10)),
    );
    expect(expired.isValidAt(DateTime.utc(2026, 9, 27)), isFalse);
    final cert = parseOpenSshUserCert(base64Encode(_certBlob()));
    expect(
      cert.matchesPublicBlob(OpensshEcdsaP256.publicBlobFromPoint(
        Uint8List.fromList([0x04, ...List<int>.filled(64, 9)]),
      )),
      isFalse,
    );
  });
}
