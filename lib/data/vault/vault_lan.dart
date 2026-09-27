import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kelola/domain/vault/vault_transport.dart';

class VaultLanSession {
  VaultLanSession({
    required this.token,
    required HttpServer server,
    required SimpleKeyPair keyPair,
  }) : _server = server,
       _keyPair = keyPair;

  final String token;
  final HttpServer _server;
  final SimpleKeyPair _keyPair;
  List<int>? _received;

  static Future<VaultLanSession> offer() async {
    final keyPair = await X25519().newKeyPair();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final pub = await keyPair.extractPublicKey();
    final ip = await _lanAddress();
    final token =
        'kelola-vault-lan:1:$ip:${server.port}:${base64UrlEncode(pub.bytes)}';
    final session = VaultLanSession(
      token: token,
      server: server,
      keyPair: keyPair,
    );
    server.listen(session._onRequest);
    return session;
  }

  static Future<void> send(String token, List<int> blob) async {
    final parts = token.split(':');
    if (parts.length < 5 || parts[0] != 'kelola-vault-lan') {
      throw const FormatException('Not a Kelola LAN vault token');
    }
    final host = parts[2];
    final port = int.parse(parts[3]);
    final peerPub = SimplePublicKey(
      base64Url.decode(parts.sublist(4).join(':')),
      type: KeyPairType.x25519,
    );
    final keyPair = await X25519().newKeyPair();
    final shared = await X25519().sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: peerPub,
    );
    final localPub = await keyPair.extractPublicKey();
    final wrapped = await _wrap(blob, shared);
    final client = HttpClient();
    try {
      final req = await client.post(host, port, '/vault');
      req.headers.contentType = ContentType.binary;
      req.add(utf8.encode(jsonEncode({
        'pub': base64Encode(localPub.bytes),
        'blob': base64Encode(wrapped),
      })));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw StateError('LAN vault send failed');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> wait() async {
    for (var i = 0; i < 600 && _received == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final blob = _received;
    if (blob == null) {
      throw StateError('LAN vault receive timed out');
    }
    return blob;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _onRequest(HttpRequest request) async {
    try {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      final peerPub = SimplePublicKey(
        base64Decode(body['pub'] as String),
        type: KeyPairType.x25519,
      );
      final shared = await X25519().sharedSecretKey(
        keyPair: _keyPair,
        remotePublicKey: peerPub,
      );
      _received = await _unwrap(
        base64Decode(body['blob'] as String),
        shared,
      );
      request.response.statusCode = 200;
    } catch (_) {
      request.response.statusCode = 400;
    } finally {
      await request.response.close();
    }
  }

  static Future<String> _lanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }
}

class LanVaultTransport implements VaultTransport {
  LanVaultTransport(this._blob);

  final List<int> _blob;

  @override
  VaultTransportKind get kind => VaultTransportKind.lan;

  @override
  Future<void> write(List<int> blob) async {}

  @override
  Future<List<int>> read() async => _blob;
}

Future<List<int>> _wrap(List<int> blob, SecretKey key) async {
  final nonce = Uint8List.fromList(
    List<int>.generate(12, (_) => Random.secure().nextInt(256)),
  );
  final box = await AesGcm.with256bits().encrypt(
    blob,
    secretKey: key,
    nonce: nonce,
  );
  return utf8.encode(
    jsonEncode({
      'nonce': base64Encode(nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    }),
  );
}

Future<List<int>> _unwrap(List<int> wrapped, SecretKey key) async {
  final header = jsonDecode(utf8.decode(wrapped)) as Map;
  final clear = await AesGcm.with256bits().decrypt(
    SecretBox(
      base64Decode(header['ciphertext'] as String),
      nonce: base64Decode(header['nonce'] as String),
      mac: Mac(base64Decode(header['mac'] as String)),
    ),
    secretKey: key,
  );
  return clear;
}
