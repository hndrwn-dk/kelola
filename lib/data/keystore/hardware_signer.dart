import 'dart:typed_data';

import 'package:kelola/domain/facts/enums.dart';

abstract class HardwareSigner {
  Future<HardwareKey> generateKey(String alias);

  Future<Uint8List> sign(String alias, Uint8List data);

  Future<bool> keyExists(String alias);

  Future<void> deleteKey(String alias);
}

class HardwareKey {
  const HardwareKey({
    required this.alias,
    required this.publicKeySpki,
    required this.backend,
    required this.authRequired,
  });

  final String alias;
  final Uint8List publicKeySpki;
  final KeyBackend backend;
  final bool authRequired;
}

class HardwareSignerException implements Exception {
  HardwareSignerException(this.message);

  final String message;

  @override
  String toString() => message;
}
