import 'package:flutter/services.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/domain/facts/enums.dart';

class MethodChannelHardwareSigner implements HardwareSigner {
  MethodChannelHardwareSigner({
    MethodChannel channel = const MethodChannel(
      'labs.tursina.kelola/hardware_signer',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<HardwareKey> generateKey(String alias) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'generateKey',
      {'alias': alias},
    );
    if (raw == null) {
      throw HardwareSignerException('generateKey returned nothing');
    }
    return HardwareKey(
      alias: alias,
      publicKeySpki: _bytes(raw['publicKeySpki']),
      backend: _backend(raw['backend'] as String?),
      authRequired: raw['authRequired'] as bool? ?? false,
    );
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('sign', {
      'alias': alias,
      'data': data,
    });
    if (raw == null) {
      throw HardwareSignerException('sign returned nothing');
    }
    return _bytes(raw);
  }

  static Uint8List _bytes(dynamic raw) {
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is List) {
      return Uint8List.fromList(raw.cast<int>());
    }
    throw HardwareSignerException('expected bytes, got ${raw.runtimeType}');
  }

  @override
  Future<bool> keyExists(String alias) async {
    return await _channel.invokeMethod<bool>('keyExists', {'alias': alias}) ??
        false;
  }

  @override
  Future<void> deleteKey(String alias) {
    return _channel.invokeMethod<void>('deleteKey', {'alias': alias});
  }

  static KeyBackend _backend(String? name) {
    switch (name) {
      case 'strongbox':
        return KeyBackend.strongbox;
      case 'secureEnclave':
        return KeyBackend.secureEnclave;
      case 'tee':
        return KeyBackend.tee;
      case 'software':
        return KeyBackend.software;
      default:
        return KeyBackend.unknown;
    }
  }
}
