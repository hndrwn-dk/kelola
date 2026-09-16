import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/stable_host_inventory.dart';

Host _host(
  String alias, {
  HostAttention attention = HostAttention.unknown,
  DateTime? attentionAt,
}) {
  return Host(
    id: alias,
    alias: alias,
    address: '10.0.0.1',
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    attention: attention,
    attentionAt: attentionAt,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 9, 4);

  test('a host that becomes unreachable leaves healthy immediately', () {
    final stable = StableHostInventory();
    stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.healthy,
          attentionAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      allowReorder: true,
      now: now,
    );
    final next = stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.unreachable,
          attentionAt: now,
        ),
      ],
      allowReorder: false,
      now: now,
    );
    expect(next.healthy, isEmpty);
    expect(next.needsAttention.map((h) => h.alias), ['ok']);
    expect(next.summary, '1 · 1 needs attention');
  });

  test('attention change without allowReorder keeps surviving order', () {
    final stable = StableHostInventory();
    final first = stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.healthy,
          attentionAt: now.subtract(const Duration(minutes: 1)),
        ),
        _host('pending'),
      ],
      allowReorder: true,
      now: now,
    );
    expect(first.healthy.map((h) => h.alias), ['ok']);
    expect(first.notChecked.map((h) => h.alias), ['pending']);

    final moved = stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.failedUnits,
          attentionAt: now,
        ),
        _host('pending'),
      ],
      allowReorder: false,
      now: now,
    );
    expect(moved.healthy, isEmpty);
    expect(moved.needsAttention.map((h) => h.alias), ['ok']);
    expect(moved.notChecked.map((h) => h.alias), ['pending']);
  });

  test('allowReorder re-buckets after attention change', () {
    final stable = StableHostInventory();
    stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.healthy,
          attentionAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      allowReorder: true,
      now: now,
    );
    final next = stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.failedUnits,
          attentionAt: now,
        ),
      ],
      allowReorder: true,
      now: now,
    );
    expect(next.needsAttention.map((h) => h.alias), ['ok']);
    expect(next.healthy, isEmpty);
  });

  test('new member appears in notChecked without reshuffling others', () {
    final stable = StableHostInventory();
    stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.healthy,
          attentionAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      allowReorder: true,
      now: now,
    );
    final next = stable.project(
      [
        _host(
          'ok',
          attention: HostAttention.healthy,
          attentionAt: now.subtract(const Duration(minutes: 1)),
        ),
        _host('new'),
      ],
      allowReorder: false,
      now: now,
    );
    expect(next.healthy.map((h) => h.alias), ['ok']);
    expect(next.notChecked.map((h) => h.alias), ['new']);
  });
}
