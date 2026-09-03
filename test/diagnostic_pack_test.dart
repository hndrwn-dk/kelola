import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/diagnostic_pack.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/probes/df_pt_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

Host _host() {
  return const Host(
    id: 'h1',
    alias: 'nas-01',
    address: '10.0.0.8',
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    attention: HostAttention.failedUnits,
    failedUnitCount: 2,
    diskRootPercent: 91,
  );
}

HostFacts _facts() {
  return const HostFacts(
    osId: 'ubuntu',
    osVersionId: '24.04',
    prettyName: 'Ubuntu 24.04 LTS',
    init: InitSystem.systemd,
    systemdVersion: 255,
    pkg: PackageManager.apt,
    fw: FirewallBackend.ufw,
    hasJournald: true,
    journalReadable: true,
    arch: 'x86_64',
    nprocCores: 4,
    nics: [
      HostNic(
        name: 'eth0',
        mac: 'aa:bb:cc:dd:ee:ff',
        ipv4: '10.0.0.8',
      ),
    ],
  );
}

void main() {
  test('pack includes redacted facts, attention, failed units, journal, df, versions',
      () {
    final pack = buildDiagnosticPack(
      host: _host(),
      facts: _facts(),
      failedUnits: const ['nginx.service', 'borgmatic.service'],
      journal: const [
        JournalEntry(
          cursor: '1',
          realtimeUsec: '1000',
          priority: 3,
          message: 'bind failed on nas-01 as hendra',
          unit: 'nginx.service',
        ),
      ],
      dfPt: 'Filesystem     Type  1024-blocks  Used Available Capacity Mounted on\n'
          '/dev/sda1      ext4     1048576  900000    148576      86% /\n',
    );
    expect(pack, contains('attention: failedUnits'));
    expect(pack, contains('nginx.service'));
    expect(pack, contains('borgmatic.service'));
    expect(pack, contains('df -PT'));
    expect(pack, contains('kelola: 0.1.0'));
    expect(pack, contains('flutter: 3.47'));
    expect(pack, contains('<HOST_'));
    expect(pack, isNot(contains('nas-01')));
    expect(pack, isNot(contains('hendra')));
    expect(pack, isNot(contains('10.0.0.8')));
    expect(pack, isNot(contains('aa:bb:cc:dd:ee:ff')));
    expect(pack, contains('<MAC_'));
    expect(pack, contains('<USER_'));
  });

  test('journal in the pack is capped at 50 lines', () {
    final lines = List.generate(
      60,
      (i) => JournalEntry(
        cursor: '$i',
        realtimeUsec: '${1000 + i}',
        priority: 6,
        message: 'line $i',
        unit: 'nginx.service',
      ),
    );
    final pack = buildDiagnosticPack(
      host: _host(),
      facts: _facts(),
      failedUnits: const [],
      journal: lines,
      dfPt: '',
    );
    expect(RegExp(r'line \d+').allMatches(pack), hasLength(50));
    expect(pack, isNot(contains('line 50')));
    expect(pack, contains('line 49'));
  });

  test('private key material never survives the pack', () {
    const blob = 'AAAAB3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final pack = buildDiagnosticPack(
      host: _host(),
      facts: _facts(),
      failedUnits: const [],
      journal: const [
        JournalEntry(
          cursor: '1',
          realtimeUsec: '1',
          priority: 6,
          message: 'authorized_keys ssh-ed25519 $blob comment',
        ),
      ],
      dfPt: 'BEGIN OPENSSH PRIVATE KEY\n$blob\n',
    );
    expect(pack, isNot(contains(blob)));
    expect(pack, isNot(contains('kelola-user')));
    expect(pack, contains('<REDACTED>'));
  });

  test('df -PT probe is read-only', () {
    expect(const DfPtProbe().risk, RiskLevel.read);
    expect(const DfPtProbe().command(HostFacts.undiscovered), contains('df -PT'));
  });

  test('pack builder uses the shared M7 redactor, not a second table', () {
    final src = File('lib/domain/incident/diagnostic_pack.dart').readAsStringSync();
    expect(src, contains('package:kelola/domain/redaction/redact.dart'));
    expect(src, contains('redactText('));
    expect(
      File('lib/presentation/widgets/diagnostic_pack_sheet.dart')
          .readAsStringSync(),
      contains('JournalProbe(limit: 50)'),
    );
    expect(
      File('lib/presentation/widgets/diagnostic_pack_sheet.dart')
          .readAsStringSync(),
      contains('Share.share'),
    );
  });
}
