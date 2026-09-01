import 'dart:typed_data';

import 'package:kelola/data/ssh/ssh_wire.dart';

/// ASN.1 DER ECDSA signature <-> SSH `mpint r || mpint s`.
///
/// Android Keystore and iOS Secure Enclave emit DER. SSH wants mpints.
/// Silent auth failures almost always start here.
class DerEcdsaSignature {
  const DerEcdsaSignature(this.r, this.s);

  final BigInt r;
  final BigInt s;

  factory DerEcdsaSignature.parse(Uint8List der) {
    var i = 0;
    if (der.isEmpty || der[i++] != 0x30) {
      throw const FormatException('ECDSA signature is not a DER SEQUENCE');
    }
    final seq = _readLength(der, i);
    i = seq.next;
    final end = i + seq.length;
    if (end > der.length) {
      throw const FormatException('truncated DER SEQUENCE');
    }

    if (i >= end || der[i++] != 0x02) {
      throw const FormatException('ECDSA signature missing INTEGER r');
    }
    final rLen = _readLength(der, i);
    i = rLen.next;
    if (i + rLen.length > end) {
      throw const FormatException('truncated INTEGER r');
    }
    final rBytes = der.sublist(i, i + rLen.length);
    i += rLen.length;

    if (i >= end || der[i++] != 0x02) {
      throw const FormatException('ECDSA signature missing INTEGER s');
    }
    final sLen = _readLength(der, i);
    i = sLen.next;
    if (i + sLen.length > end) {
      throw const FormatException('truncated INTEGER s');
    }
    final sBytes = der.sublist(i, i + sLen.length);

    return DerEcdsaSignature(_integer(rBytes), _integer(sBytes));
  }

  Uint8List toDer() {
    final rBytes = _encodeInt(r);
    final sBytes = _encodeInt(s);
    final body = BytesBuilder(copy: false)
      ..add([0x02])
      ..add(_encodeLength(rBytes.length))
      ..add(rBytes)
      ..add([0x02])
      ..add(_encodeLength(sBytes.length))
      ..add(sBytes);
    final content = body.takeBytes();
    return Uint8List.fromList([
      0x30,
      ..._encodeLength(content.length),
      ...content,
    ]);
  }

  /// Inner SSH signature blob: mpint r || mpint s.
  Uint8List toSshBlob() {
    final w = SshWireWriter()
      ..writeMpint(r)
      ..writeMpint(s);
    return w.takeBytes();
  }

  /// Full SSH signature: string type || string blob.
  Uint8List toSshSignature({String type = 'ecdsa-sha2-nistp256'}) {
    final w = SshWireWriter()
      ..writeUtf8(type)
      ..writeString(toSshBlob());
    return w.takeBytes();
  }

  factory DerEcdsaSignature.fromSshBlob(Uint8List blob) {
    final r = SshWireReader(blob);
    return DerEcdsaSignature(r.readMpint(), r.readMpint());
  }

  static BigInt _integer(List<int> bytes) {
    if (bytes.isEmpty) {
      return BigInt.zero;
    }
    return BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }

  static Uint8List _encodeInt(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) {
      hex = '0$hex';
    }
    var bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0x00, ...bytes]);
    }
    return bytes;
  }

  static ({int length, int next}) _readLength(Uint8List der, int offset) {
    if (offset >= der.length) {
      throw const FormatException('truncated DER length');
    }
    final first = der[offset];
    if (first < 0x80) {
      return (length: first, next: offset + 1);
    }
    final count = first & 0x7f;
    if (count == 0 || offset + 1 + count > der.length) {
      throw const FormatException('invalid DER length');
    }
    var length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | der[offset + 1 + i];
    }
    return (length: length, next: offset + 1 + count);
  }

  static List<int> _encodeLength(int length) {
    if (length < 0x80) {
      return [length];
    }
    if (length <= 0xff) {
      return [0x81, length];
    }
    return [0x82, (length >> 8) & 0xff, length & 0xff];
  }
}
