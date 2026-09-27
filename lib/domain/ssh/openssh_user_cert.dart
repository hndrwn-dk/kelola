import 'dart:convert';
import 'dart:typed_data';

import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/ssh_wire.dart';

const kOpenSshEcdsaUserCertType = 'ecdsa-sha2-nistp256-cert-v01@openssh.com';
const kOpenSshCertTypeUser = 1;

class OpenSshUserCert {
  const OpenSshUserCert({
    required this.blob,
    required this.innerPublicBlob,
    required this.serial,
    required this.keyId,
    required this.principals,
    required this.validAfter,
    required this.validBefore,
  });

  final Uint8List blob;
  final Uint8List innerPublicBlob;
  final int serial;
  final String keyId;
  final List<String> principals;
  final int validAfter;
  final int validBefore;

  bool isValidAt(DateTime now) {
    final epoch = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (validAfter != 0 && epoch < validAfter) {
      return false;
    }
    if (validBefore != 0 && epoch >= validBefore) {
      return false;
    }
    return true;
  }

  bool matchesPublicBlob(Uint8List publicBlob) {
    if (innerPublicBlob.length != publicBlob.length) {
      return false;
    }
    for (var i = 0; i < innerPublicBlob.length; i++) {
      if (innerPublicBlob[i] != publicBlob[i]) {
        return false;
      }
    }
    return true;
  }
}

OpenSshUserCert parseOpenSshUserCert(String raw) {
  final blob = _decodeCert(raw);
  final reader = SshWireReader(blob);
  final type = reader.readUtf8();
  if (type != kOpenSshEcdsaUserCertType) {
    throw FormatException('unsupported certificate type $type');
  }
  reader.readString(); // nonce
  final curve = reader.readUtf8();
  if (curve != OpensshEcdsaP256.curve) {
    throw FormatException('unsupported certificate curve $curve');
  }
  final point = reader.readString();
  final serial = reader.readUint64();
  final certType = reader.readUint32();
  if (certType != kOpenSshCertTypeUser) {
    throw FormatException('certificate is not a user cert');
  }
  final keyId = reader.readUtf8();
  final principals = _readPrincipals(reader.readString());
  final validAfter = reader.readUint64();
  final validBefore = reader.readUint64();
  reader.readString(); // critical options
  reader.readString(); // extensions
  reader.readString(); // reserved
  reader.readString(); // signature key
  reader.readString(); // signature
  return OpenSshUserCert(
    blob: blob,
    innerPublicBlob: OpensshEcdsaP256.publicBlobFromPoint(point),
    serial: serial,
    keyId: keyId,
    principals: principals,
    validAfter: validAfter,
    validBefore: validBefore,
  );
}

Uint8List _decodeCert(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('certificate is empty');
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  final b64 = parts.length >= 2 && parts.first.contains('cert-v01')
      ? parts[1]
      : parts.first;
  return Uint8List.fromList(base64Decode(b64));
}

List<String> _readPrincipals(Uint8List packed) {
  if (packed.isEmpty) {
    return const [];
  }
  final reader = SshWireReader(packed);
  final names = <String>[];
  while (true) {
    try {
      names.add(reader.readUtf8());
    } on FormatException {
      break;
    }
  }
  return names;
}
