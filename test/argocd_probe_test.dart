import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/probes/argo_probes.dart';
import 'package:kelola/domain/risk/risk_level.dart';

String _fixture(String name) =>
    File('test/fixtures/argocd/$name').readAsStringSync();

HostFacts _facts(String runtime) =>
    HostFacts.undiscovered.copyWith(runtimes: [runtime]);

const _check = 'auth can-i list applications.argoproj.io --all-namespaces';
const _get = 'get applications.argoproj.io -A -o json';

void main() {
  final readAt = DateTime.utc(2026, 11, 10, 9, 6);

  group('ArgoAppsProbe command', () {
    for (final runtime in ['kubectl', 'k3s']) {
      test('$runtime checks the reader before ---APPS---', () {
        final cmd = ArgoAppsProbe.commandFor(_facts(runtime));
        expect(cmd, contains(_check));
        expect(cmd, contains('---READER_DENIED---'));
        expect(cmd.indexOf(_check), lessThan(cmd.indexOf('echo ---APPS---')));
        expect(cmd, contains(kelolaReaderKubeconfig));
        expect(cmd, contains(_get));
        expect(cmd, contains('|| '));
        expect(cmd, contains('---APPS_ERR---'));
        expect(cmd, contains('KELOLA_ERR '));
      });
    }

    test('oc has no reader check and no reader kubeconfig', () {
      final cmd = ArgoAppsProbe.commandFor(_facts('oc'));
      expect(cmd, isNot(contains(_check)));
      expect(cmd, isNot(contains('READER_DENIED')));
      expect(cmd, isNot(contains(kelolaReaderKubeconfig)));
      expect(cmd, contains(_get));
      expect(cmd, contains('---APPS---'));
    });

    test('no kubectl says so', () {
      expect(
        ArgoAppsProbe.commandFor(HostFacts.undiscovered),
        'echo ---NO_KUBECTL---',
      );
    });

    test('never uses the argocd binary', () {
      for (final r in ['kubectl', 'k3s', 'oc']) {
        expect(ArgoAppsProbe.commandFor(_facts(r)), isNot(contains('argocd ')));
      }
    });

    test('metadata is a read', () {
      const p = ArgoAppsProbe();
      expect(p.risk, RiskLevel.read);
      expect(p.needsSudo, isFalse);
      expect(p.timeout, const Duration(seconds: 30));
      expect(p.auditTitle, 'Read Argo CD applications');
      expect(
        const FleetArgoProbe().auditTitle,
        'Read Argo CD applications (fleet)',
      );
    });
  });

  group('parse', () {
    test('uses the injected clock', () {
      final p = ArgoAppsProbe(now: () => readAt);
      final r = p.parse(
        '---APPS---\n${_fixture('apps_guestbook_synced.json')}\n',
        '',
        0,
      );
      expect(r.readAt, readAt);
      expect(r.apps.single.name, 'guestbook');
    });

    test('defaults readAt to now in UTC', () {
      final r = const ArgoAppsProbe().parse(
        '---APPS---\n${_fixture('apps_guestbook_synced.json')}\n',
        '',
        0,
      );
      expect(r.readAt.isUtc, isTrue);
    });
  });

  group('FleetArgoProbe', () {
    test('same command as the home read', () {
      for (final r in ['kubectl', 'k3s', 'oc']) {
        final f = _facts(r);
        expect(const FleetArgoProbe().command(f), ArgoAppsProbe.commandFor(f));
      }
    });

    test('returns apps on the guestbook fixture', () {
      final r = FleetArgoProbe(now: () => readAt).parse(
        '---APPS---\n${_fixture('apps_guestbook_synced.json')}\n',
        '',
        0,
      );
      expect(r.error, isNull);
      expect(r.apps.single.name, 'guestbook');
    });

    test('throws K8sReadException with the short reason when forbidden', () {
      expect(
        () => FleetArgoProbe(now: () => readAt)
            .parse(_fixture('apps_forbidden.txt'), '', 0),
        throwsA(
          isA<K8sReadException>()
              .having((e) => e.what, 'what', 'Argo CD applications')
              .having((e) => e.detail, 'detail', 'Forbidden'),
        ),
      );
    });
  });
}
