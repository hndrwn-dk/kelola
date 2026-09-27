import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kelola/domain/vault/vault.dart';

class VaultPassphraseException implements Exception {
  @override
  String toString() => 'Vault passphrase was rejected';
}

class VaultKdfParams {
  const VaultKdfParams({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
  });

  static const production = VaultKdfParams(
    memoryKib: 19456,
    iterations: 2,
    parallelism: 1,
  );

  static const test = VaultKdfParams(
    memoryKib: 8,
    iterations: 1,
    parallelism: 1,
  );

  final int memoryKib;
  final int iterations;
  final int parallelism;
}

Future<String> sealVault(
  VaultPlaintext plain,
  String passphrase, {
  VaultKdfParams params = VaultKdfParams.production,
  Random? random,
}) async {
  final rng = random ?? Random.secure();
  final salt = Uint8List.fromList([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
  final nonce = Uint8List.fromList([for (var i = 0; i < 12; i++) rng.nextInt(256)]);
  final key = await _derive(passphrase, salt, params);
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(encodeVaultPlaintext(plain))),
    secretKey: key,
    nonce: nonce,
  );
  return jsonEncode({
    'vaultSchemaVersion': kVaultSchemaVersion,
    'kdf': 'argon2id',
    'memoryKib': params.memoryKib,
    'iterations': params.iterations,
    'parallelism': params.parallelism,
    'salt': base64Encode(salt),
    'nonce': base64Encode(nonce),
    'mac': base64Encode(box.mac.bytes),
    'ciphertext': base64Encode(box.cipherText),
  });
}

Future<VaultPlaintext> openVault(String blob, String passphrase) async {
  Map<String, Object?> header;
  try {
    header = Map<String, Object?>.from(jsonDecode(blob) as Map);
  } catch (_) {
    throw VaultPassphraseException();
  }
  final version = header['vaultSchemaVersion'] as int? ?? 0;
  if (version > kVaultSchemaVersion) {
    throw VaultVersionUnsupported(version);
  }
  try {
    final params = VaultKdfParams(
      memoryKib: header['memoryKib'] as int? ?? VaultKdfParams.production.memoryKib,
      iterations: header['iterations'] as int? ?? VaultKdfParams.production.iterations,
      parallelism:
          header['parallelism'] as int? ?? VaultKdfParams.production.parallelism,
    );
    final key = await _derive(
      passphrase,
      base64Decode(header['salt'] as String),
      params,
    );
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(header['ciphertext'] as String),
        nonce: base64Decode(header['nonce'] as String),
        mac: Mac(base64Decode(header['mac'] as String)),
      ),
      secretKey: key,
    );
    return decodeVaultPlaintext(
      Map<String, Object?>.from(jsonDecode(utf8.decode(clear)) as Map),
    );
  } catch (e) {
    if (e is VaultVersionUnsupported) {
      rethrow;
    }
    throw VaultPassphraseException();
  }
}

Future<SecretKey> _derive(
  String passphrase,
  List<int> salt,
  VaultKdfParams params,
) {
  return Argon2id(
    parallelism: params.parallelism,
    memory: params.memoryKib,
    iterations: params.iterations,
    hashLength: 32,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);
}
