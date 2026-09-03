import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/domain/deep_link.dart';

void main() {
  Host host({
    required String id,
    required String alias,
    required HostAttention attention,
    int? failed,
    DateTime? at,
  }) {
    return Host(
      id: id,
      alias: alias,
      address: '10.0.0.$id',
      port: 22,
      username: 'ops',
      keyAlias: 'kelola',
      attention: attention,
      failedUnitCount: failed,
      attentionAt: at,
    );
  }

  final now = DateTime.utc(2026, 9, 4, 1, 0);

  test('widget is off by default and shows no host', () {
    final snap = pickWorstHostSnapshot(
      [
        host(
          id: '1',
          alias: 'nas-01',
          attention: HostAttention.failedUnits,
          failed: 3,
          at: now,
        ),
      ],
      enabled: false,
      now: now,
    );
    expect(snap.enabled, isFalse);
    expect(snap.hostId, isNull);
    expect(formatHomeWidget(snap, now: now), 'Widget off');
  });

  test('enabled widget shows worst host, failed count, and age', () {
    final snap = pickWorstHostSnapshot(
      [
        host(
          id: '2',
          alias: 'edge',
          attention: HostAttention.healthy,
          failed: 0,
          at: now.subtract(const Duration(minutes: 3)),
        ),
        host(
          id: '1',
          alias: 'nas-01',
          attention: HostAttention.failedUnits,
          failed: 3,
          at: now.subtract(const Duration(minutes: 20)),
        ),
      ],
      enabled: true,
      now: now,
    );
    expect(snap.hostId, '1');
    expect(snap.alias, 'nas-01');
    expect(snap.failedCount, 3);
    final text = formatHomeWidget(snap, now: now);
    expect(text, contains('nas-01'));
    expect(text, contains('3 failed'));
    expect(text, contains('ago'));
  });

  test('publish path never opens SSH', () {
    final dart = File('lib/domain/widget/home_widget_snapshot.dart')
        .readAsStringSync();
    expect(dart, isNot(contains('session_pool')));
    expect(dart, isNot(contains('dartssh2')));
    expect(dart, isNot(contains('SshSessionPool')));
    expect(dart, isNot(contains('.execute(')));

    final pub = File('lib/domain/widget/publish_home_widget.dart')
        .readAsStringSync();
    expect(pub, contains('repo.list()'));
    expect(pub, isNot(contains('session_pool')));
    expect(pub, isNot(contains('dartssh2')));
    expect(pub, isNot(contains('.execute(')));

    final bridge = File('lib/data/widget/home_widget_bridge.dart')
        .readAsStringSync();
    expect(bridge, isNot(contains('session_pool')));
    expect(bridge, isNot(contains('dartssh2')));
  });

  test('native widget provider does not start SSH', () {
    final kt = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/StatusWidgetProvider.kt',
    ).readAsStringSync();
    expect(kt.toLowerCase(), isNot(contains('ssh')));
    expect(kt, isNot(contains('ProcessBuilder')));
    expect(kt, contains('SharedPreferences'));
    expect(kt, contains('kelola://host/'));
    expect(kt, contains('/incident'));
  });

  test('tap link opens incident for that host', () {
    final link = parseKelolaLink('kelola://host/abc/incident');
    expect(link.hostId, 'abc');
    expect(link.incident, isTrue);
    expect(parseKelolaLink('kelola://host/abc').incident, isFalse);
  });

  test('schema 7 adds widgetEnabled default false', () {
    final src = File('lib/data/db/database.dart').readAsStringSync();
    expect(src, contains('schemaVersion => 7'));
    expect(src, contains('if (from < 7)'));
    expect(src, contains('widgetEnabled'));
    final tables = File('lib/data/db/tables.dart').readAsStringSync();
    expect(tables, contains('widgetEnabled'));
    expect(tables, contains('Constant(false)'));
  });
}
