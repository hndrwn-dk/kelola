import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';

Host _host({
  HostAttention attention = HostAttention.unknown,
  int? failedUnitCount,
  int? diskRootPercent,
  DateTime? attentionAt,
  bool readOnly = false,
}) {
  return Host(
    id: 'h1',
    alias: 'nas-01',
    address: '192.168.1.24',
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    attention: attention,
    failedUnitCount: failedUnitCount,
    diskRootPercent: diskRootPercent,
    attentionAt: attentionAt,
    readOnly: readOnly,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 2, 8);

  test('never-opened host has no attention pill', () {
    expect(_host().attentionPill(now: now), isNull);
    expect(_host().isAttentionStale(now: now), isFalse);
  });

  test('fresh failed count matches S05', () {
    final h = _host(
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 78,
      attentionAt: now.subtract(const Duration(minutes: 2)),
    );
    expect(h.attentionPill(now: now), '2 failed');
    expect(h.isAttentionStale(now: now), isFalse);
  });

  test('stale failed count is labelled with age', () {
    final h = _host(
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 78,
      attentionAt: now.subtract(const Duration(days: 3)),
    );
    expect(h.isAttentionStale(now: now), isTrue);
    expect(h.attentionPill(now: now), '2 failed · 3d ago');
  });

  test('fresh high disk matches S05', () {
    final h = _host(
      attention: HostAttention.diskHigh,
      failedUnitCount: 0,
      diskRootPercent: 91,
      attentionAt: now.subtract(const Duration(minutes: 1)),
    );
    expect(h.attentionPill(now: now), 'disk 91%');
  });

  test('reading older than 15 minutes is stale', () {
    final fresh = _host(
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 40,
      attentionAt: now.subtract(const Duration(minutes: 14)),
    );
    final stale = _host(
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 40,
      attentionAt: now.subtract(const Duration(minutes: 16)),
    );
    expect(fresh.isAttentionStale(now: now), isFalse);
    expect(fresh.attentionPill(now: now), 'healthy');
    expect(stale.isAttentionStale(now: now), isTrue);
    expect(stale.attentionPill(now: now), 'healthy · 16m ago');
  });
}
