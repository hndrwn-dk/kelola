import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';

/// Fixture text without its leading `# synthetic` line.
String _fixture(String name) => File('test/fixtures/argocd/$name')
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.startsWith('# synthetic'))
    .join('\n');

HostFacts _facts(List<String> runtimes) =>
    HostFacts.undiscovered.copyWith(runtimes: runtimes);

/// A ClusterHealthProbe stdout with [argo] between OPENSHIFT and CONTEXT.
String _clusterOut({
  String readyz = 'ok',
  String nodes = '{"items":[]}',
  String? argo,
  String auth = '',
}) {
  return [
    '---HOSTNAME---',
    'node-a',
    '---READYZ---',
    readyz,
    '---NODES---',
    nodes,
    '---OPENSHIFT---',
    '---OPENSHIFT_NONE---',
    ?argo,
    '---CONTEXT---',
    'default',
    '---AUTH---',
    auth,
  ].join('\n');
}

void main() {
  group('Argo CD command', () {
    test('section sits between OPENSHIFT and CONTEXT', () {
      final cmd = const ClusterHealthProbe().command(_facts(['kubectl']));
      final os = cmd.indexOf('echo ---OPENSHIFT---');
      final argo = cmd.indexOf('echo ---ARGO_CRD---');
      final ctx = cmd.indexOf('echo ---CONTEXT---');
      expect(os, greaterThanOrEqualTo(0));
      expect(argo, greaterThan(os));
      expect(ctx, greaterThan(argo));
    });

    test('command skips Argo when readyz failed', () {
      final cmd = const ClusterHealthProbe().command(_facts(['kubectl']));
      expect(cmd, contains(r'if [ "$readyz_failed" != 1 ]; then'));
      final start = cmd.indexOf(r'if [ "$readyz_failed" != 1 ]; then');
      final argo = cmd.indexOf('echo ---ARGO_CRD---');
      final end = cmd.indexOf('\nfi\n', start);
      expect(argo, greaterThan(start));
      expect(end, greaterThan(argo));
    });

    test('CRD read uses kubectlTry, namespaced fallback uses the reader', () {
      final cmd = const ClusterHealthProbe().command(_facts(['kubectl']));
      expect(
        cmd,
        contains(
          r'argo_crd=$( { kubectl get crd applications.argoproj.io -o name '
          '--request-timeout=5s 2>/dev/null || sudo -n kubectl get crd '
          'applications.argoproj.io -o name --request-timeout=5s || '
          '{ echo ---ARGO_CRD_FAIL---; { kubectl get crd '
          'applications.argoproj.io -o name --request-timeout=5s || '
          'sudo -n kubectl get crd applications.argoproj.io -o name '
          '--request-timeout=5s; } 2>&1 >/dev/null | $kubectlDecisiveLines; }; } '
          '2>/dev/null )',
        ),
      );
      expect(cmd, contains(r"printf '%s\n' " '"\$argo_crd"'));
      expect(
        cmd,
        contains(
          r'case "$argo_crd" in *orbidden*) echo ---ARGO_NS---; '
          r'{ [ -r "$HOME/.kube/kelola.yaml" ] && LC_ALL=C kubectl '
          r'--kubeconfig="$HOME/.kube/kelola.yaml" get '
          'applications.argoproj.io -A -o name --request-timeout=5s '
          '2>/dev/null || kubectl get applications.argoproj.io -A -o name '
          '--request-timeout=5s 2>/dev/null || sudo -n kubectl get '
          'applications.argoproj.io -A -o name --request-timeout=5s && '
          'echo ---ARGO_NS_OK---; } 2>&1 | $kubectlDecisiveLines ;; esac',
        ),
      );
    });

    for (final runtimes in [
      ['k3s'],
      ['oc'],
    ]) {
      test('${runtimes.first} flavor carries the Argo section', () {
        final cmd = const ClusterHealthProbe().command(_facts(runtimes));
        expect(cmd, contains('echo ---ARGO_CRD---'));
        expect(cmd, contains('echo ---ARGO_CRD_FAIL---'));
        expect(cmd, contains('echo ---ARGO_NS---'));
        expect(cmd, contains('esac'));
      });
    }

    test('no kubectl: no Argo section', () {
      final cmd = const ClusterHealthProbe().command(_facts(['docker']));
      expect(cmd, isNot(contains('ARGO')));
    });
  });

  group('parseHasArgo', () {
    test('no ARGO_CRD section → null', () {
      expect(parseHasArgo(_clusterOut()), isNull);
      expect(parseHasArgo(''), isNull);
    });

    test('CRD name listed → true', () {
      expect(parseHasArgo(_fixture('crd_present.txt')), isTrue);
    });

    test('namespaced read answered → true', () {
      expect(parseHasArgo(_fixture('crd_forbidden_ns_ok.txt')), isTrue);
    });

    test('CRD section empty, no FAIL marker → false', () {
      expect(parseHasArgo('---ARGO_CRD---\n\n---CONTEXT---\ndefault'),
          isFalse);
    });

    test('CRD NotFound → false', () {
      expect(parseHasArgo(_fixture('crd_absent.txt')), isFalse);
    });

    test('forbidden CRD, namespaced read: no such type → false', () {
      expect(parseHasArgo(_fixture('crd_forbidden.txt')), isFalse);
    });

    test('forbidden CRD and forbidden namespaced read → null', () {
      expect(parseHasArgo(_fixture('crd_forbidden_ns_forbidden.txt')),
          isNull);
    });

    test('shell "command not found" is not evidence → null', () {
      expect(
        parseHasArgo('---ARGO_CRD---\n---ARGO_CRD_FAIL---\n'
            'The connection to the server localhost:8080 was refused\n'
            'sudo: kubectl: command not found'),
        isNull,
      );
      expect(
        parseHasArgo('---ARGO_CRD---\n---ARGO_CRD_FAIL---\n'
            'sh: kubectl: not found'),
        isNull,
      );
    });

    test('a decisive line behind discovery noise still decides', () {
      final noise = List.filled(
        6,
        'E1110 09:06:00.000000 1 memcache.go:265] couldn\'t get current '
        'server API group list: Get "http://localhost:8080/api": dial tcp '
        '127.0.0.1:8080: connect: connection refused',
      ).join('\n');
      // What kubectlDecisiveLines leaves: the decisive line, then the last.
      expect(
        parseHasArgo('---ARGO_CRD---\n---ARGO_CRD_FAIL---\n'
            'Error from server (NotFound): customresourcedefinitions'
            '.apiextensions.k8s.io "applications.argoproj.io" not found\n'
            'The connection to the server localhost:8080 was refused'),
        isFalse,
      );
      expect(
        parseHasArgo('---ARGO_CRD---\n---ARGO_CRD_FAIL---\n$noise\n'
            'Error from server (Forbidden): customresourcedefinitions is '
            'forbidden\n---ARGO_NS---\n---ARGO_NS_OK---'),
        isTrue,
      );
    });

    test('anything else → null', () {
      expect(
        parseHasArgo('---ARGO_CRD---\n---ARGO_CRD_FAIL---\n'
            'Unable to connect to the server: i/o timeout'),
        isNull,
      );
      expect(parseHasArgo('---ARGO_CRD---\nsomething odd'), isNull);
    });
  });

  group('ClusterHealth.hasArgo', () {
    test('parseClusterHealth fills hasArgo from the Argo section', () {
      final h = parseClusterHealth(
          _clusterOut(argo: _fixture('crd_present.txt')));
      expect(h.hasArgo, isTrue);
      expect(h.isOpenShift, isFalse);
      expect(h.kubeContext, 'default');
      expect(
        parseClusterHealth(_clusterOut(argo: _fixture('crd_absent.txt')))
            .hasArgo,
        isFalse,
      );
      expect(parseClusterHealth(_clusterOut()).hasArgo, isNull);
    });

    test('withCoreDns keeps hasArgo', () {
      final h = parseClusterHealth(
          _clusterOut(argo: _fixture('crd_present.txt')));
      expect(h.withCoreDns(true).hasArgo, isTrue);
      expect(h.withCoreDns(true).coreDnsReady, isTrue);
    });

    test('expired login → hasArgo null', () {
      final h = parseClusterHealth(_clusterOut(
        readyz: '---READYZ_FAIL---',
        argo: _fixture('crd_present.txt'),
        auth: 'error: You must be logged in to the server (Unauthorized)',
      ));
      expect(h.authExpired, isTrue);
      expect(h.hasArgo, isNull);
    });
  });

  test('FleetClusterProbe still counts nodes only', () {
    const probe = FleetClusterProbe();
    final argo = _fixture('crd_forbidden_ns_ok.txt');
    final empty = probe.parse(_clusterOut(nodes: '', argo: argo), '', 0);
    expect(empty.nodesRead, isFalse);
    expect(empty.health.hasArgo, isTrue);
    final read = probe.parse(_clusterOut(argo: argo), '', 0);
    expect(read.nodesRead, isTrue);
  });
  // Runs the awk stage for real. Windows has no POSIX sh on PATH in CI.
  group('kubectlDecisiveLines in a shell', skip: Platform.isWindows, () {
    Future<String> filter(String input) async {
      final r = await Process.run('sh', [
        '-c',
        'printf \'%s\n\' "\$IN" | $kubectlDecisiveLines',
      ], environment: {'IN': input});
      expect(r.exitCode, 0);
      return (r.stdout as String).trim();
    }

    const memcache =
        'E1110 memcache.go:265] couldn\'t get current server API group '
        'list: dial tcp 127.0.0.1:8080: connect: connection refused';
    final noise = List.filled(6, memcache).join('\n');
    const refused = 'The connection to the server localhost:8080 was refused';
    const forbidden = 'Error from server (Forbidden): customresourcedefinitions'
        '.apiextensions.k8s.io "applications.argoproj.io" is forbidden';
    const notFound = 'Error from server (NotFound): customresourcedefinitions'
        '.apiextensions.k8s.io "applications.argoproj.io" not found';

    test('six memcache lines then Forbidden: Forbidden kept', () async {
      expect(await filter('$noise\n$forbidden'), forbidden);
    });

    test('NotFound before sudo noise: NotFound kept, plus the last line',
        () async {
      final out = await filter('$notFound\n$noise\n$refused');
      expect(out, '$notFound\n$refused');
      expect(parseHasArgo('---ARGO_CRD---\n---ARGO_CRD_FAIL---\n$out'),
          isFalse);
    });

    test('Forbidden before noise still reaches the namespaced read', () async {
      final out = await filter('$forbidden\n$noise\n$refused');
      expect(out, contains('orbidden'));
    });

    test('no decisive line: the last two lines', () async {
      expect(await filter('$noise\n$refused'), '$memcache\n$refused');
      expect(await filter('only one line'), 'only one line');
    });

    test('the namespaced read keeps its OK marker after a Forbidden',
        () async {
      expect(
        await filter('$forbidden\napplication.argoproj.io/guestbook\n'
            '---ARGO_NS_OK---'),
        '$forbidden\n---ARGO_NS_OK---',
      );
    });
  });
}
