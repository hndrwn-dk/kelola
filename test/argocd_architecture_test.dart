import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/probes/argo_probes.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// M49 architecture pins. Argo CD support is read-only, secret-free and adds
/// no gate, schema change or assistant path.
const _domainFiles = [
  'lib/domain/argocd/argo_app.dart',
  'lib/domain/argocd/argo_parser.dart',
  'lib/domain/argocd/argo_filters.dart',
  'lib/domain/probes/argo_probes.dart',
];

const _screenFiles = [
  'lib/presentation/screens/argo_apps_screen.dart',
  'lib/presentation/screens/argo_app_detail_screen.dart',
  'lib/presentation/widgets/argo_gitops_block.dart',
  'lib/presentation/widgets/argo_resource_sheet.dart',
];

const _newFiles = [..._domainFiles, ..._screenFiles];

const _changedFiles = [
  'lib/domain/probes/cluster_health_probe.dart',
  'lib/domain/k8s/cluster_kind.dart',
  'lib/data/k8s/cluster_kind_store.dart',
  'lib/domain/fleet/fleet_k8s.dart',
  'lib/domain/k8s/k8s_reader.dart',
];

String _read(String path) => File(path).readAsStringSync();

List<HostFacts> _factsPerFlavor() => [
      for (final runtimes in [
        ['oc'],
        ['kubectl'],
        ['k3s'],
        ['oc', 'kubectl'],
      ])
        HostFacts.undiscovered.copyWith(runtimes: runtimes),
    ];

void main() {
  test('Argo probes are risk == read and pass the fleet gate', () {
    const probes = <Probe<dynamic>>[
      ArgoAppsProbe(),
      FleetArgoProbe(),
      ClusterHealthProbe(),
    ];
    for (final p in probes) {
      expect(p.risk, RiskLevel.read, reason: p.runtimeType.toString());
      expect(p.needsSudo, isFalse, reason: p.runtimeType.toString());
      expect(
        () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
        returnsNormally,
        reason: p.runtimeType.toString(),
      );
    }
  });

  test('no Argo command uses the argocd binary or a mutating verb', () {
    const probes = <Probe<dynamic>>[
      ArgoAppsProbe(),
      FleetArgoProbe(),
      ClusterHealthProbe(),
    ];
    final mutating = RegExp(r'\b(annotate|patch|apply|delete)\b');
    for (final facts in _factsPerFlavor()) {
      for (final p in probes) {
        final cmd = p.command(facts);
        final reason = '${p.runtimeType} ${facts.runtimes}';
        expect(cmd, isNot(contains('argocd ')), reason: reason);
        expect(mutating.hasMatch(cmd), isFalse, reason: reason);
      }
    }
  });

  test('FleetArgoProbe runs exactly the detail command', () {
    for (final facts in _factsPerFlavor()) {
      expect(
        const FleetArgoProbe().command(facts),
        const ArgoAppsProbe().command(facts),
      );
    }
  });

  test('the Argo parser never reads input fields that can hold secrets', () {
    final src = _read('lib/domain/argocd/argo_parser.dart');
    final banned = RegExp(
      r'\b(values|valuesObject|parameters|fileParameters|env|patches|jsonnet)\b',
    );
    expect(banned.firstMatch(src)?.group(0), isNull);
    expect(src, isNot(contains("'info'")));
    expect(src, isNot(contains('"info"')));
  });

  test('no Argo file adds a ProFeature value or a gate call', () {
    for (final path in _newFiles) {
      final src = _read(path);
      expect(src, isNot(contains('ProFeature')), reason: path);
      expect(src, isNot(contains('isUnlocked')), reason: path);
    }
  });

  test('M49 adds no Drift table and no schema change', () {
    for (final path in _newFiles) {
      final src = _read(path);
      expect(src, isNot(contains('extends Table')), reason: path);
      expect(src, isNot(contains('schemaVersion')), reason: path);
      expect(src, isNot(contains('MigrationStrategy')), reason: path);
    }
    expect(
      _read('lib/data/db/database.dart'),
      contains('int get schemaVersion => 28;'),
    );
  });

  test('no Argo file imports the assistant or the LLM client', () {
    final imp = RegExp(r'''import\s+['"][^'"]*(data/llm|assistant)''');
    for (final path in _newFiles) {
      expect(imp.hasMatch(_read(path)), isFalse, reason: path);
    }
  });

  test('no Argo file logs', () {
    final logging = RegExp(r'(^|[^A-Za-z0-9_.])(print|debugPrint|log)\(');
    for (final path in _newFiles) {
      final src = _read(path);
      expect(logging.hasMatch(src), isFalse, reason: path);
      expect(src, isNot(contains('developer.log')), reason: path);
    }
  });

  test('caches keep only summary fields', () {
    for (final path in [
      'lib/data/k8s/cluster_kind_store.dart',
      'lib/domain/fleet/fleet_k8s.dart',
    ]) {
      final src = _read(path);
      expect(src, isNot(contains('rawJson')), reason: path);
      expect(src, isNot(contains('stdout')), reason: path);
    }
  });

  test('Argo screens use the design system only', () {
    for (final path in _screenFiles) {
      final src = _read(path);
      expect(src, isNot(contains('AlertDialog')), reason: path);
      expect(src, isNot(contains('Color(0x')), reason: path);
      expect(src, isNot(contains('FloatingActionButton')), reason: path);
      expect(RegExp(r'\b(Card|ListTile)\(').hasMatch(src), isFalse,
          reason: path);
    }
  });

  test('every fixture the README lists exists and is marked synthetic', () {
    const dir = 'test/fixtures/argocd';
    final readme = _read('$dir/README.md');
    final listed = RegExp(r'^\| `([^`]+)` \|', multiLine: true)
        .allMatches(readme)
        .map((m) => m.group(1)!)
        .toList();
    expect(listed, isNotEmpty);

    final onDisk = Directory(dir)
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/').split('/').last)
        .where((n) => n != 'README.md')
        .toList()
      ..sort();
    expect([...listed]..sort(), onDisk);

    for (final name in listed) {
      final file = File('$dir/$name');
      expect(file.existsSync(), isTrue, reason: name);
      final text = file.readAsStringSync();
      if (name.endsWith('.json')) {
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['_synthetic'], isTrue, reason: name);
      }
      expect(readme.contains('| `$name` | synthetic |'), isTrue, reason: name);
    }
  });

  test('changed files named by the task still exist', () {
    for (final path in _changedFiles) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
