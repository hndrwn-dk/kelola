import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:kelola/domain/vault/vault_transport.dart';

/// Max accepted POST /vault body size (encrypted envelope JSON).
const int vaultLanMaxBodyBytes = 8 * 1024 * 1024;

/// Picks the first non-loopback IPv4 address, or null when none exist.
String? pickLanAddress(Iterable<InternetAddress> addresses) {
  for (final addr in addresses) {
    if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
      return addr.address;
    }
  }
  return null;
}

class VaultLanSession {
  VaultLanSession({
    required this.token,
    required HttpServer server,
    required SimpleKeyPair keyPair,
    Duration offerTimeout = const Duration(seconds: 60),
    this.maxBodyBytes = vaultLanMaxBodyBytes,
  }) : _server = server,
       _keyPair = keyPair {
    _server.listen(_onRequest);
    _timeout = Timer(offerTimeout, () {
      unawaited(close());
    });
  }

  final String token;
  final HttpServer _server;
  final SimpleKeyPair _keyPair;
  final int maxBodyBytes;
  List<int>? _received;
  Timer? _timeout;
  bool _closed = false;

  InternetAddress get boundAddress => _server.address;

  int get boundPort => _server.port;

  bool get hasReceived => _received != null;

  bool get isClosed => _closed;

  static Future<List<InternetAddress>> _defaultListAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final iface in interfaces)
        for (final addr in iface.addresses) addr,
    ];
  }

  static Future<VaultLanSession> offer({
    Future<List<InternetAddress>> Function()? listAddresses,
    String? Function(List<InternetAddress> addresses)? pickAddress,
    Duration offerTimeout = const Duration(seconds: 60),
  }) async {
    final addresses = await (listAddresses ?? _defaultListAddresses)();
    final ip = (pickAddress ?? pickLanAddress)(addresses);
    if (ip == null) {
      throw StateError('Connect both phones to the same Wi-Fi.');
    }
    return offerOn(
      InternetAddress(ip),
      offerTimeout: offerTimeout,
    );
  }

  @visibleForTesting
  static Future<VaultLanSession> offerOn(
    InternetAddress address, {
    Duration offerTimeout = const Duration(seconds: 60),
    int maxBodyBytes = vaultLanMaxBodyBytes,
  }) async {
    final keyPair = await X25519().newKeyPair();
    final server = await HttpServer.bind(address, 0);
    final pub = await keyPair.extractPublicKey();
    final token =
        'kelola-vault-lan:1:${address.address}:${server.port}:'
        '${base64UrlEncode(pub.bytes)}';
    return VaultLanSession(
      token: token,
      server: server,
      keyPair: keyPair,
      offerTimeout: offerTimeout,
      maxBodyBytes: maxBodyBytes,
    );
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
    for (var i = 0; i < 600 && _received == null && !_closed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final blob = _received;
    if (blob == null) {
      throw StateError('LAN vault receive timed out');
    }
    return blob;
  }

  Future<void> close() async {
    _timeout?.cancel();
    _timeout = null;
    if (_closed) {
      return;
    }
    _closed = true;
    await _server.close(force: true);
  }

  Future<void> _onRequest(HttpRequest request) async {
    var status = HttpStatus.ok;
    try {
      if (request.uri.path != '/vault') {
        status = HttpStatus.notFound;
        return;
      }
      if (request.method != 'POST') {
        status = HttpStatus.methodNotAllowed;
        return;
      }
      if (request.contentLength > maxBodyBytes) {
        status = HttpStatus.requestEntityTooLarge;
        // Must consume the body or the response may never flush.
        await for (final _ in request) {}
        return;
      }
      final bodyBytes = await _readBodyCapped(request, maxBodyBytes);
      if (bodyBytes == null) {
        status = HttpStatus.requestEntityTooLarge;
        return;
      }
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map;
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
      status = HttpStatus.ok;
    } catch (_) {
      if (status == HttpStatus.ok && _received == null) {
        status = HttpStatus.badRequest;
      }
    } finally {
      request.response.statusCode = status;
      if (status != HttpStatus.ok) {
        request.response.headers.set(HttpHeaders.connectionHeader, 'close');
      }
      await request.response.close();
      if (_received != null) {
        await close();
      }
    }
  }
}

Future<List<int>?> _readBodyCapped(HttpRequest request, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  var overflow = false;
  await for (final chunk in request) {
    if (overflow) {
      continue;
    }
    if (builder.length + chunk.length > maxBytes) {
      overflow = true;
      builder.clear();
      continue;
    }
    builder.add(chunk);
  }
  if (overflow) {
    return null;
  }
  return builder.takeBytes();
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
