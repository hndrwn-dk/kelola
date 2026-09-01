import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/der_ecdsa.dart';

void main() {
  group('DerEcdsaSignature', () {
    test('round-trips r and s through DER', () {
      final original = DerEcdsaSignature(
        BigInt.parse('12345678901234567890'),
        BigInt.parse('98765432109876543210'),
      );
      final parsed = DerEcdsaSignature.parse(original.toDer());
      expect(parsed.r, original.r);
      expect(parsed.s, original.s);
    });

    test('round-trips through SSH mpint blob', () {
      final original = DerEcdsaSignature(
        BigInt.parse('ff' * 32, radix: 16),
        BigInt.parse('01${'00' * 31}', radix: 16),
      );
      final blob = original.toSshBlob();
      final parsed = DerEcdsaSignature.fromSshBlob(blob);
      expect(parsed.r, original.r);
      expect(parsed.s, original.s);
    });

    test('DER integer with high bit set is still unsigned ECDSA r', () {
      final r = BigInt.parse('f' * 64, radix: 16);
      final original = DerEcdsaSignature(r, BigInt.one);
      final der = original.toDer();
      expect(der[0], 0x30);
      final parsed = DerEcdsaSignature.parse(der);
      expect(parsed.r, r);
      expect(parsed.toSshSignature().isNotEmpty, isTrue);
    });

    test('rejects truncated input', () {
      expect(
        () => DerEcdsaSignature.parse(Uint8List.fromList([0x30, 0x0a])),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
