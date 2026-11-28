import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/k8s/cluster_kind_store.dart';
import 'package:kelola/domain/argocd/argo_parser.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/probes/argo_probes.dart';

/// Owner addition 2: raw `kubectl get applications -o json` stdout never
/// reaches the audit log, an error label, a cache or a log line.
const _secrets = [
  'info-secret',
  'fp-secret-file',
  'p4ram-secret',
  's3cr3t-helm-value',
  'plugin-env-secret',
  'kustomize-patch-secret',
  'jsonnet-ext-secret',
  'jsonnet-tla-secret',
  'VAULT_TOKEN',
  'charts.example.com',
  'git.example.com',
];

final _readAt = DateTime.utc(2026, 11, 10, 9, 10);

String _raw() =>
    '---APPS---\n${File('test/fixtures/argocd/apps_helm_secrets.json').readAsStringSync()}\n';

void _expectClean(String text, {required String reason}) {
  for (final s in [..._secrets, '"apiVersion"']) {
    expect(text, isNot(contains(s)), reason: '$reason leaked $s');
  }
}

String _methodParams(String src, String name) {
  final m = RegExp('Future<[^>]+> $name\\(([\\s\\S]*?)\\)\\s*(async|\\{)')
      .firstMatch(src);
  expect(m, isNotNull, reason: name);
  return m!.group(1)!;
}

void main() {
  final facts = HostFacts.undiscovered.copyWith(runtimes: ['kubectl']);

  test('the fixture really carries the secrets the pins look for', () {
    final raw = _raw();
    for (final s in _secrets) {
      expect(raw, contains(s));
    }
  });

  test('audit drafts carry neither output nor fixture secrets', () {
    for (final probe in [const ArgoAppsProbe(), const FleetArgoProbe()]) {
      final d = AuditDraft.fromProbe(probe, facts);
      _expectClean(d.command, reason: '${probe.runtimeType} command');
      _expectClean(d.title, reason: '${probe.runtimeType} title');
    }
  });

  test('audit methods take no output parameter', () {
    final src = File('lib/data/db/host_repository.dart').readAsStringSync();
    for (final name in ['beginAudit', 'finishAudit', 'recordAudit']) {
      final params = _methodParams(src, name);
      expect(
        RegExp(r'\b(stdout|stderr|output|rawJson|body)\b').hasMatch(params),
        isFalse,
        reason: '$name($params)',
      );
    }
  });

  test('the session pool hands stdout only to the parser and the journal log',
      () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    final uses = RegExp(r'result\.stdout').allMatches(src).toList();
    expect(uses, isNotEmpty);

    var journal = 0;
    var parse = 0;
    var keyInstall = 0;
    for (final u in uses) {
      final before = src.substring(u.start > 200 ? u.start - 200 : 0, u.start);
      final lastCall = [
        'logJournalProbeReceive(',
        'parseProbeExec(',
        'install.parse(',
      ].map((c) => MapEntry(c, before.lastIndexOf(c))).reduce(
            (a, b) => a.value >= b.value ? a : b,
          );
      expect(
        lastCall.value,
        greaterThanOrEqualTo(0),
        reason: 'result.stdout at ${u.start} is not in a known call',
      );
      switch (lastCall.key) {
        case 'logJournalProbeReceive(':
          journal++;
        case 'parseProbeExec(':
          parse++;
        default:
          keyInstall++;
      }
    }
    expect(journal, 1);
    expect(parse, 1);
    expect(keyInstall, 1);

    final guard = src.indexOf('if (probe is JournalProbe) {');
    expect(guard, greaterThan(0));
    final parseAt = src.indexOf('parseProbeExec(', guard);
    final logAt = src.indexOf('logJournalProbeReceive(', guard);
    expect(logAt, greaterThan(guard));
    expect(logAt, lessThan(parseAt));
    // The guard's block closes (first `}` after the log call) before
    // parseProbeExec starts, so the log call never sees other probes.
    final closeAt = src.indexOf('}', logAt);
    expect(closeAt, greaterThan(logAt));
    expect(closeAt, lessThan(parseAt));
    expect(src.indexOf('logJournalProbeReceive(', logAt + 1), -1);
  });

  test('a failed fleet read throws a label with no stdout text', () {
    const junkBodies = [
      '---APPS---\n{"items": [{"spec": {"info": "info-secret"}} not json\n'
          'oops s3cr3t-helm-value https://git.example.com/x.git\n',
      '---APPS---\n',
      'garbage with p4ram-secret and no marker',
    ];
    for (final body in junkBodies) {
      Object? caught;
      try {
        FleetArgoProbe(now: () => _readAt).parse(body, '', 0);
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<K8sReadException>(), reason: body);
      final label = caught.toString();
      _expectClean(label, reason: 'exception text');
      expect(label, isNot(contains('oops')));
      expect(label.length, lessThan(120));
    }
  });

  test('the fleet cache keeps counts only', () {
    final apps = parseArgoApps(_raw(), readAt: _readAt);
    expect(apps.error, isNull);
    expect(apps.apps, isNotEmpty);
    final summary = FleetK8sSummary(
      read: true,
      apiReachable: true,
      nodesReady: 1,
      nodesTotal: 1,
      argo: FleetArgoSummary.from(apps),
    );
    final encoded = summary.encode();
    expect(encoded, contains('"argo"'));
    _expectClean(encoded, reason: 'fleet cache');
    expect(encoded, isNot(contains('http')));
    expect(encoded, isNot(contains('payments')));
  });

  test('the cluster-kind cache keeps the hasArgo flag only', () async {
    final dir = Directory.systemTemp.createTempSync('kelola_argo_kind_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/cluster_kind.json');
    final store = ClusterKindStore(file);
    await store.recordRead(
      'host-1',
      const ClusterHealth(
        apiReachable: true,
        controlPlaneReady: 1,
        controlPlaneDesired: 1,
        isOpenShift: false,
        kubeContext: 'lab',
        hasArgo: true,
      ),
      _readAt,
    );
    final text = file.readAsStringSync();
    expect(text, contains('"argo":true'));
    _expectClean(text, reason: 'cluster_kind.json');
    expect(text, isNot(contains('http')));
    expect((await store.read('host-1'))?.hasArgo, isTrue);
  });
}
