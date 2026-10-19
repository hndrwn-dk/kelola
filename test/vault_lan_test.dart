import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/vault/vault_lan.dart';

/// flutter_test installs an HttpClient stub that always returns 400.
/// Vault LAN exercises a real loopback HttpServer, so restore dart:io clients.
class _IoHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      return HttpClient(context: context);
    } finally {
      HttpOverrides.global = previous;
    }
  }
}

void main() {
  setUp(() {
    HttpOverrides.global = _IoHttpOverrides();
  });
  tearDown(() {
    HttpOverrides.global = null;
  });

  test('pickLanAddress skips loopback and returns first IPv4 LAN', () {
    expect(pickLanAddress(const []), isNull);
    expect(pickLanAddress([InternetAddress.loopbackIPv4]), isNull);
    expect(
      pickLanAddress([
        InternetAddress.loopbackIPv4,
        InternetAddress('192.168.1.40'),
      ]),
      '192.168.1.40',
    );
  });

  test('offer throws when no LAN address is available', () async {
    await expectLater(
      VaultLanSession.offer(listAddresses: () async => const []),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Connect both phones to the same Wi-Fi.',
        ),
      ),
    );
  });

  test('offer binds only the resolved LAN address', () async {
    final session = await VaultLanSession.offer(
      listAddresses: () async => [InternetAddress.loopbackIPv4],
      // Treat loopback as a resolved LAN IP so the bind can be asserted
      // without requiring a real Wi-Fi interface in CI.
      pickAddress: (addrs) => addrs.first.address,
    );
    addTearDown(session.close);

    expect(session.boundAddress.address, '127.0.0.1');
    expect(session.token.split(':')[2], '127.0.0.1');
  });

  test('server closes after first accepted blob', () async {
    final session = await VaultLanSession.offerOn(InternetAddress.loopbackIPv4);
    addTearDown(() async {
      try {
        await session.close();
      } catch (_) {}
    });

    final blob = utf8.encode('vault-bytes');
    await VaultLanSession.send(session.token, blob);
    final received = await session.wait();
    expect(received, blob);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(session.isClosed, isTrue);
  });

  test('server closes after the 60 s timeout', () async {
    final session = await VaultLanSession.offerOn(
      InternetAddress.loopbackIPv4,
      offerTimeout: const Duration(milliseconds: 80),
    );
    addTearDown(() async {
      try {
        await session.close();
      } catch (_) {}
    });

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(session.isClosed, isTrue);
  });

  test('non-POST /vault requests get 404/405 and do not count as received',
      () async {
    final session = await VaultLanSession.offerOn(InternetAddress.loopbackIPv4);
    addTearDown(session.close);

    final port = session.boundPort;
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final get = await client.get('127.0.0.1', port, '/vault');
    final getRes = await get.close();
    expect(getRes.statusCode, 405);
    await getRes.drain<void>();

    final postOther = await client.post('127.0.0.1', port, '/other');
    postOther.write('x');
    final otherRes = await postOther.close();
    expect(otherRes.statusCode, 404);
    await otherRes.drain<void>();

    expect(session.hasReceived, isFalse);
  });

  test('vaultLanMaxBodyBytes is 8 MB', () {
    expect(vaultLanMaxBodyBytes, 8 * 1024 * 1024);
  });

  test('body over the size cap is rejected with 413', () async {
    const cap = 64;
    final session = await VaultLanSession.offerOn(
      InternetAddress.loopbackIPv4,
      maxBodyBytes: cap,
    );
    addTearDown(session.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final req = await client.post('127.0.0.1', session.boundPort, '/vault');
    req.headers.contentType = ContentType.binary;
    req.add(Uint8List(cap + 1));
    final res = await req.close().timeout(const Duration(seconds: 5));
    expect(res.statusCode, 413);
    await res.drain<void>();
    expect(session.hasReceived, isFalse);
  });

  test('round-trip encrypts and delivers blob over LAN token', () async {
    final session = await VaultLanSession.offerOn(InternetAddress.loopbackIPv4);
    addTearDown(session.close);

    final blob = utf8.encode('{"hosts":[]}');
    await VaultLanSession.send(session.token, blob);
    expect(await session.wait(), blob);
  });
}
