import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/search/inventory_search.dart';

Host host(
  String alias, {
  String address = '10.0.0.1',
  String? note,
  HostAttention attention = HostAttention.healthy,
}) {
  return Host(
    id: alias,
    alias: alias,
    address: address,
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    note: note,
    attention: attention,
  );
}

void main() {
  test('search matches alias, address, and notes locally', () {
    final hosts = [
      host('nas-01', address: '192.168.1.24', note: 'living-room NAS'),
      host('web-prod', address: '10.0.4.11'),
    ];
    expect(const InventorySearch().query(hosts, 'nas').single.alias, 'nas-01');
    expect(
      const InventorySearch().query(hosts, '10.0.4').single.alias,
      'web-prod',
    );
    expect(
      const InventorySearch().query(hosts, 'living-room').single.alias,
      'nas-01',
    );
  });

  test('attention sort puts failed units first', () {
    final hosts = [
      host('ok'),
      host('web-prod', attention: HostAttention.diskHigh),
      host('nas-01', attention: HostAttention.failedUnits),
    ];
    final sorted = sortByAttention(hosts);
    expect(sorted.first.alias, 'nas-01');
    expect(sorted[1].alias, 'web-prod');
  });
}
