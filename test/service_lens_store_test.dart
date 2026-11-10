import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/services/service_lens_store.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/providers.dart';

ServiceDetection _det({String version = '1.24.0', DateTime? at}) =>
    ServiceDetection(
      services: [
        DetectedService(
          id: ServiceId.nginx,
          state: ServiceState.running,
          unit: 'nginx.service',
          version: version,
          binaries: const {'nginx': '/usr/sbin/nginx'},
        ),
      ],
      listeningPorts: const [80, 443],
      readAt: at ?? DateTime.utc(2026, 11, 4, 10),
    );

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kelola_lens');
    file = File('${dir.path}/service_lens.json');
  });

  tearDown(() => dir.delete(recursive: true));

  test('write then read', () async {
    await ServiceLensStore(file).write('h1', _det());
    final back = await ServiceLensStore(file).read('h1');
    expect(back, isNotNull);
    expect(back!.readAt, DateTime.utc(2026, 11, 4, 10));
    expect(back.listeningPorts, [80, 443]);
    expect(back.services.single.id, ServiceId.nginx);
    expect(back.services.single.version, '1.24.0');
    expect(back.services.single.binaries['nginx'], '/usr/sbin/nginx');
    expect(await ServiceLensStore(file).read('other'), isNull);
  });

  test('readAll returns all hosts', () async {
    final store = ServiceLensStore(file);
    await store.write('h1', _det());
    await store.write('h2', _det(version: '1.26.0'));
    final all = await ServiceLensStore(file).readAll();
    expect(all.keys.toSet(), {'h1', 'h2'});
    expect(all['h2']!.services.single.version, '1.26.0');
  });

  test('remove forgets host', () async {
    final store = ServiceLensStore(file);
    await store.write('h1', _det());
    await store.write('h2', _det());
    await store.remove('h1');
    expect(await store.read('h1'), isNull);
    expect(await ServiceLensStore(file).read('h2'), isNotNull);
    await store.remove('never-there');
  });

  test('corrupt file reads as empty and next write succeeds', () async {
    file.writeAsStringSync('{not json');
    final store = ServiceLensStore(file);
    expect(await store.readAll(), isEmpty);
    expect(await store.read('h1'), isNull);
    await store.write('h1', _det());
    expect(await ServiceLensStore(file).read('h1'), isNotNull);
    expect(jsonDecode(file.readAsStringSync()), isA<Map>());
  });

  test('junk entries are skipped, good ones kept', () async {
    file.writeAsStringSync(
      jsonEncode({
        'bad': 'x',
        'worse': {'at': 'nope'},
        'good': _det().toJson(),
      }),
    );
    final all = await ServiceLensStore(file).readAll();
    expect(all.keys, ['good']);
  });

  test('concurrent writes are all kept', () async {
    final store = ServiceLensStore(file);
    await Future.wait([
      for (var i = 0; i < 10; i++) store.write('h$i', _det()),
    ]);
    expect((await ServiceLensStore(file).readAll()).length, 10);
  });

  test('memory store round-trips', () async {
    final store = ServiceLensStore.memory();
    await store.write('h1', _det());
    expect((await store.read('h1'))!.listeningPorts, [80, 443]);
    await store.remove('h1');
    expect(await store.readAll(), isEmpty);
  });

  test(
    'forgetServiceLens removes the entry and swallows a failing store',
    () async {
      final store = ServiceLensStore.memory();
      await store.write('h1', _det());
      await forgetServiceLens(Future.value(store), 'h1');
      expect(await store.read('h1'), isNull);
      await forgetServiceLens(Future.error(StateError('no dir')), 'h1');
    },
  );
}
