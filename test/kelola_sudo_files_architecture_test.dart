import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo/kelola_sudo_files.dart';

// Pins for Host details → Kelola sudo rules: the remove probe is destructive,
// never runs from the fleet, and never names a file Kelola did not write.

List<File> _dart(String dir) => [
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e,
];

String _norm(String p) => p.replaceAll(r'\', '/');

/// Every absolute path under /etc a script names.
Set<String> _etcPaths(String script) => {
  for (final m in RegExp(r"/etc/[^\s'" '"' r';|)]*').allMatches(script)) m[0]!,
};

const _line = 'alice ALL=(root) NOPASSWD: /usr/sbin/reboot ""';

void main() {
  test('removal is destructive and the fleet gate refuses it', () {
    for (final path in kelolaOwnedSudoersFiles) {
      for (final p in [
        KelolaSudoRemoveProbe(path: path),
        KelolaSudoRemoveProbe(path: path, line: _line),
      ]) {
        expect(p.risk, RiskLevel.destructive);
        expect(
          () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
          throwsA(isA<FleetReadOnlyViolation>()),
        );
      }
    }
    // The read is read-only, so the fleet could run it, but nothing there
    // does (below).
    expect(const KelolaSudoFilesProbe().risk, RiskLevel.read);
  });

  test('nothing in the fleet references the sudo files probes', () {
    final fleet = [
      ..._dart('lib/presentation/fleet'),
      ..._dart('lib/domain/fleet'),
      File('lib/presentation/screens/fleet_screen.dart'),
    ];
    expect(fleet, isNotEmpty);
    for (final f in fleet) {
      final src = f.readAsStringSync();
      for (final banned in const [
        'KelolaSudoRemoveProbe',
        'KelolaSudoFilesProbe',
        'kelola_sudo_files.dart',
        'kelola_sudo_rules_flow.dart',
        'removeKelolaSudoRule',
      ]) {
        expect(src, isNot(contains(banned)), reason: '${f.path}: $banned');
      }
    }
  });

  test('the scripts name only the three Kelola files', () {
    for (final path in kelolaOwnedSudoersFiles) {
      for (final p in [
        KelolaSudoRemoveProbe(path: path),
        KelolaSudoRemoveProbe(path: path, line: _line),
      ]) {
        expect(_etcPaths(p.command(HostFacts.undiscovered)), {path});
      }
    }
    for (final p in const [
      KelolaSudoFilesProbe(),
      KelolaSudoFilesProbe(withPassword: true),
    ]) {
      expect(_etcPaths(p.command(HostFacts.undiscovered)), {
        ...kelolaOwnedSudoersFiles,
        // Only searched (`[ -x ]`), never listed or globbed.
        if (!p.withPassword) '/etc/sudoers.d',
      });
    }
  });

  test('the source has no sudoers path of its own and no glob', () {
    final src = File('lib/domain/sudo/kelola_sudo_files.dart').readAsStringSync();
    // The three paths come from their constants; the only literal is the
    // directory the read checks is searchable.
    expect(RegExp(r"'/etc/[^']*'").allMatches(src).map((m) => m[0]).toSet(), {
      "'/etc/sudoers.d'",
    });
    expect(src, isNot(contains('sudoers.d/*')));
    // Never a listing of the directory.
    expect(src, isNot(contains('ls /etc')));
    expect(src, isNot(contains('find /etc')));
    for (final path in kelolaOwnedSudoersFiles) {
      for (final p in <Probe<Object?>>[
        KelolaSudoRemoveProbe(path: path),
        const KelolaSudoFilesProbe(),
      ]) {
        final s = p.command(HostFacts.undiscovered);
        expect(s, isNot(contains('ls ')));
        expect(s, isNot(contains('find ')));
      }
    }
  });

  test('lib builds the remove probe in one place and never passes the test dir', () {
    final builders = <String>[];
    for (final f in _dart('lib')) {
      final src = f.readAsStringSync();
      expect(src, isNot(contains('sudoersDir:')), reason: f.path);
      if (src.contains('KelolaSudoRemoveProbe(')) builders.add(_norm(f.path));
    }
    expect(builders.toSet(), {
      'lib/domain/sudo/kelola_sudo_files.dart',
      'lib/presentation/widgets/kelola_sudo_rules_flow.dart',
    });
    // The flow asks for presence before it runs the probe.
    final flow = File(
      'lib/presentation/widgets/kelola_sudo_rules_flow.dart',
    ).readAsStringSync();
    expect(
      flow.indexOf('requireDestructivePresence('),
      lessThan(flow.indexOf('probe: probe')),
    );
  });

  test('host details removes through the destructive sheet only', () {
    final src = File(
      'lib/presentation/screens/host_details_screen.dart',
    ).readAsStringSync();
    expect(src, contains('DestructiveConfirmSheet('));
    expect(src, isNot(contains('AlertDialog')));
    expect(src, contains("'Host is read-only.'"));
  });
}
