import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/workload_exec_probe.dart';

HostFacts _facts(String runtime) =>
    HostFacts.undiscovered.copyWith(runtimes: [runtime]);

const _exec = "-n 'default' exec 'pod/a' -- sh -c 'boom'";

class _Sandbox {
  _Sandbox(this.dir);

  final Directory dir;

  File get log => File('${dir.path}/calls.log');

  List<String> get calls =>
      log.existsSync() ? log.readAsLinesSync() : const [];

  void script(String name, String body) {
    final file = File('${dir.path}/$name')
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', ['+x', file.path]);
  }

  Future<ProcessResult> run(String command) {
    return Process.run(
      'sh',
      ['-c', command],
      environment: {'PATH': '${dir.path}:${Platform.environment['PATH']}'},
    );
  }
}

/// Fake kubectl. Reaches the API only as [reachesAs], and every exec fails.
String _kubectl(_Sandbox box, {required String reachesAs}) => '''
who=plain; [ -n "\$FAKE_SUDO" ] && who=sudo
if [ "\$1" = get ]; then
  [ "\$who" = "$reachesAs" ] && exit 0
  echo "\$who: connection refused" >&2
  exit 1
fi
echo "\$who \$*" >> "${box.log.path}"
case "\$*" in
  *exec*) echo "sh: boom: not found" >&2; exit 127 ;;
  *apply*) cat ;;
esac
''';

String _sudo({required bool allowed}) => allowed
    ? 'shift; FAKE_SUDO=1 exec "\$@"'
    : 'echo "sudo: a password is required" >&2; exit 1';

void main() {
  // Runs the generated shell for real. Windows has no POSIX PATH to fake.
  group('in a shell', skip: Platform.isWindows, () {
    late _Sandbox box;

    setUp(() {
      box = _Sandbox(Directory.systemTemp.createTempSync('kubectl_once'));
      addTearDown(() => box.dir.deleteSync(recursive: true));
    });

    test('a failing command runs once and keeps its exit code', () async {
      box.script('kubectl', _kubectl(box, reachesAs: 'plain'));
      box.script('sudo', _sudo(allowed: true));
      final r = await box.run(kubectlOnce(_facts('kubectl'), _exec));
      expect(box.calls, hasLength(1));
      expect(box.calls.single, startsWith('plain '));
      expect(r.exitCode, 127);
      expect(r.stderr, contains('boom: not found'));
      expect(r.stderr, isNot(contains('password')));
    });

    test('kubectl that needs root runs once through sudo', () async {
      box.script('kubectl', _kubectl(box, reachesAs: 'sudo'));
      box.script('sudo', _sudo(allowed: true));
      final r = await box.run(kubectlOnce(_facts('kubectl'), _exec));
      expect(box.calls, hasLength(1));
      expect(box.calls.single, startsWith('sudo '));
      expect(r.exitCode, 127);
    });

    test('with no way to the API the command never runs', () async {
      box.script('kubectl', _kubectl(box, reachesAs: 'nobody'));
      box.script('sudo', _sudo(allowed: false));
      final r = await box.run(kubectlOnce(_facts('kubectl'), _exec));
      expect(box.calls, isEmpty);
      expect(r.exitCode, 2);
      expect(r.stderr, contains('connection refused'));
      expect(r.stderr, contains('a password is required'));
    });

    test('k3s tries sudo first and still runs once', () async {
      box.script(
        'k3s',
        'shift\n${_kubectl(box, reachesAs: 'sudo')}',
      );
      box.script('sudo', _sudo(allowed: true));
      final r = await box.run(kubectlOnce(_facts('k3s'), _exec));
      expect(box.calls, hasLength(1));
      expect(box.calls.single, startsWith('sudo '));
      expect(r.exitCode, 127);
    });

    test('applied YAML reaches kubectl through the check', () async {
      box.script('kubectl', _kubectl(box, reachesAs: 'plain'));
      box.script('sudo', _sudo(allowed: true));
      final r = await box.run(
        kubectlStdin(_facts('kubectl'), 'apply -f -', 'a: 1\n'),
      );
      expect(r.stdout, 'a: 1\n');
      expect(r.exitCode, 0);
    });
  });

  test('no kubectl is still reported', () {
    expect(
      kubectlOnce(HostFacts.undiscovered, 'get pods'),
      contains('---NO_KUBECTL---'),
    );
  });

  group('exec results', () {
    const workload = K8sWorkload(
      kind: K8sKind.pod,
      namespace: 'default',
      name: 'a',
      ready: 1,
      desired: 1,
    );
    const probe = WorkloadExecProbe(workload: workload, line: 'x');

    test('a failure after output keeps both', () {
      final out = probe.parse('1\n2\n', 'command terminated', 1);
      expect(out, '1\n2\ncommand terminated');
    });

    test('a failure with no reason still says so', () {
      expect(probe.parse('1\n', '', 3), '1\nexit 3');
    });
  });
}
