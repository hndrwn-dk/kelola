import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/tunnel_manager.dart';

void main() {
  test('bindLoopbackEphemeral binds 127.0.0.1 with ephemeral port', () async {
    final socket = await bindLoopbackEphemeral();
    addTearDown(socket.close);

    expect(socket.address.address, '127.0.0.1');
    expect(socket.port, isNot(0));
  });

  test('lib/ never binds InternetAddress.anyIPv4', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('InternetAddress.anyIPv4')) {
        hits.add(entity.path);
      }
    }
    expect(hits, isEmpty, reason: 'loopback-only: $hits');
  });
}
