import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/network/network_parser.dart';
import 'package:kelola/domain/probes/network_list_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

String _marked({
  required String addr,
  required String route,
  required String ss,
}) {
  return '---ADDR---\n$addr\n---ROUTE---\n$route\n---SS---\n$ss\n';
}

void main() {
  const parser = NetworkParser();

  test('json addr skips loopback and keeps v4/v6', () {
    final addr = File('test/fixtures/network/ip_addr.json').readAsStringSync();
    final route = File('test/fixtures/network/ip_route.json').readAsStringSync();
    final ss = File('test/fixtures/network/ss_tulpn.txt').readAsStringSync();
    final snap = parser.parse(_marked(addr: addr, route: route, ss: ss));
    expect(snap.interfaces.map((i) => i.name), ['eth0', 'wlan0']);
    expect(snap.interfaces.first.addresses, contains('192.168.1.10/24'));
    expect(snap.interfaces.first.isUp, isTrue);
    expect(snap.interfaces.last.isUp, isFalse);
    expect(snap.routes.first.dst, 'default');
    expect(snap.routes.first.gateway, '192.168.1.1');
    expect(snap.ports, hasLength(4));
    expect(snap.ports.first.process, 'sshd');
    expect(snap.ports.first.pid, 821);
    expect(snap.ports.first.local, '0.0.0.0:22');
  });

  test('text fallback parses ip addr/route when json is absent', () {
    final addr = File('test/fixtures/network/ip_addr.txt').readAsStringSync();
    final route = File('test/fixtures/network/ip_route.txt').readAsStringSync();
    final ss = File('test/fixtures/network/ss_tulpn.txt').readAsStringSync();
    final snap = parser.parse(_marked(addr: addr, route: route, ss: ss));
    expect(snap.interfaces.map((i) => i.name), ['eth0', 'wlan0']);
    expect(snap.interfaces.first.addresses.first, '192.168.1.10/24');
    expect(snap.routes.singleWhere((r) => r.dst == 'default').dev, 'eth0');
  });

  test('probe is read-only ip -j with text fallback and ss -tulpn', () {
    const probe = NetworkListProbe();
    final cmd = probe.command(HostFacts.undiscovered);
    expect(probe.risk, RiskLevel.read);
    expect(probe.needsSudo, isFalse);
    expect(probe.auditTitle, 'Listed network');
    expect(cmd, contains('ip -j addr'));
    expect(cmd, contains('ip -j route'));
    expect(cmd, contains('ss -tulpn'));
    expect(cmd, contains('ip addr'));
    expect(cmd, contains('ip route'));
    expect(cmd, isNot(contains('ip link set')));
    expect(cmd, isNot(contains('iptables')));
  });
}
