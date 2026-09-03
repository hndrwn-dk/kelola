import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/snippets/run_snippet.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/snippets/starters.dart';

void main() {
  const bindings = SnippetBindings(
    unit: 'nginx.service',
    path: '/',
    port: '443',
    host: 'nas-01',
  );

  const host = Host(
    id: 'h1',
    alias: 'nas-01',
    address: '10.0.0.8',
    port: 22,
    username: 'ops',
    keyAlias: 'kelola',
  );

  const readOnlyHost = Host(
    id: 'h1',
    alias: 'nas-01',
    address: '10.0.0.8',
    port: 22,
    username: 'ops',
    keyAlias: 'kelola',
    readOnly: true,
  );

  test('placeholders expand; unbound placeholders refuse to become a probe', () {
    const snippet = Snippet(
      id: 's1',
      name: 'status',
      template: 'systemctl status {{unit}} --no-pager',
    );
    final probe = snippetToProbe(snippet, bindings);
    expect(probe.commandLine, contains('nginx.service'));
    expect(probe.commandLine, isNot(contains('{{')));
    expect(probe, isA<Probe>());

    expect(
      () => snippetToProbe(snippet, const SnippetBindings()),
      throwsA(isA<SnippetUnboundException>()),
    );
  });

  test('starters are risk-classified and never auto-run', () {
    final byName = {for (final s in shippedSnippets) s.name: s};
    expect(byName.keys, containsAll(['status', 'listen-on-port', 'df -PT']));
    expect(
      byName.keys.any((n) => n.toLowerCase().contains('vacuum')),
      isTrue,
    );

    final status = snippetToProbe(byName['status']!, bindings);
    expect(status.risk, RiskLevel.read);

    final listen = snippetToProbe(byName['listen-on-port']!, bindings);
    expect(listen.risk, RiskLevel.read);

    final df = snippetToProbe(byName['df -PT']!, bindings);
    expect(df.risk, RiskLevel.read);

    final vacuum = byName.entries
        .firstWhere((e) => e.key.toLowerCase().contains('vacuum'))
        .value;
    expect(snippetToProbe(vacuum, bindings).risk, RiskLevel.mutate);
  });

  test('JSON round-trips user templates', () {
    const user = Snippet(
      id: 'u1',
      name: 'mine',
      template: 'cat {{path}}',
    );
    final json = encodeSnippets([user]);
    final back = decodeSnippets(json);
    expect(back.single.name, 'mine');
    expect(back.single.template, 'cat {{path}}');
  });

  test('property: snippets cannot bypass execute(Probe)', () async {
    for (final template in _generatedTemplates(Random(4))) {
      final dispatcher = _FakeDispatcher();
      final snippet = Snippet(id: 'g', name: 'gen', template: template);
      final probe = snippetToProbe(snippet, bindings);

      try {
        await runSnippet(
          host: readOnlyHost,
          probe: probe,
          execute: dispatcher.execute,
          scope: ProbeScope.host,
        );
      } on ReadOnlyViolation {
        expect(probe.risk, isNot(RiskLevel.read));
      }

      expect(dispatcher.rawCalls, 0, reason: template);
      expect(dispatcher.probes, hasLength(1), reason: template);
      expect(dispatcher.audits, isNotEmpty, reason: template);
      if (probe.risk != RiskLevel.read) {
        expect(dispatcher.audits.single['error'], 'ReadOnlyViolation');
      }
    }
  });

  test('property: no snippet is invocable from fleet mode', () async {
    for (final template in _generatedTemplates(Random(7))) {
      final dispatcher = _FakeDispatcher();
      final snippet = Snippet(id: 'g', name: 'gen', template: template);
      final probe = snippetToProbe(snippet, bindings);
      await expectLater(
        runSnippet(
          host: host,
          probe: probe,
          execute: dispatcher.execute,
          scope: ProbeScope.fleet,
        ),
        throwsA(isA<SnippetFleetForbidden>()),
      );
      expect(dispatcher.probes, isEmpty, reason: template);
      expect(dispatcher.rawCalls, 0);
    }
  });

  test('bypass would skip read-only and audit — runner source forbids it', () {
    final runner = File('lib/domain/snippets/run_snippet.dart').readAsStringSync();
    expect(runner, contains('execute('));
    expect(runner, contains('ProbeScope.fleet'));
    expect(runner, isNot(contains('runRaw')));
    expect(runner, isNot(contains('dartssh2')));
    expect(runner, isNot(contains('SSHClient')));

    final probeSrc =
        File('lib/domain/probes/snippet_probe.dart').readAsStringSync();
    expect(probeSrc, contains('extends Probe'));
    expect(probeSrc, isNot(contains('dartssh2')));

    final ui = File('lib/presentation/screens/snippets_screen.dart')
        .readAsStringSync();
    expect(ui, contains('runSnippet'));
    expect(ui, contains('runHostProbe'));
    expect(ui, contains('ProbeScope.host'));
    expect(ui, isNot(contains('ProbeScope.fleet')));
    expect(ui, isNot(contains('initState() {\n    super.initState();\n    _run')));
    expect(ui, isNot(contains('dartssh2')));
  });

  test('schema 6 adds snippets stepwise', () {
    final src = File('lib/data/db/database.dart').readAsStringSync();
    expect(src, contains('if (from < 6)'));
    expect(src, contains('createTable(snippets)'));
  });
}

class _FakeDispatcher {
  final probes = <Probe<dynamic>>[];
  final audits = <Map<String, String?>>[];
  int rawCalls = 0;

  Future<T> execute<T>(Host host, Probe<T> probe) async {
    probes.add(probe);
    if (host.readOnly && probe.risk != RiskLevel.read) {
      audits.add({'title': probe.auditTitle, 'error': 'ReadOnlyViolation'});
      throw ReadOnlyViolation(probe);
    }
    audits.add({'title': probe.auditTitle, 'error': null});
    return probe.parse('', '', 0);
  }

  Future<void> runRaw(String command) async {
    rawCalls++;
  }
}

List<String> _generatedTemplates(Random rng) {
  const seeds = [
    'systemctl status {{unit}} --no-pager',
    'ss -lptn | grep -F :{{port}}',
    'df -PT {{path}}',
    'journalctl --vacuum-time=7d',
    'systemctl stop {{unit}}',
    'systemctl disable sshd.service',
    'cat {{path}}',
    'echo {{host}}',
    'sudo -n systemctl restart {{unit}}',
  ];
  final extra = [
    for (var i = 0; i < 12; i++) seeds[rng.nextInt(seeds.length)],
  ];
  return [...seeds, ...extra];
}
