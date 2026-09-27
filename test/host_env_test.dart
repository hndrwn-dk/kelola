import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/host_env/host_env.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';
import 'package:kelola/domain/facts/host_facts.dart';

Host _host(List<String> tags) {
  return Host(
    id: 'h1',
    alias: 'web',
    address: '10.0.0.8',
    port: 22,
    username: 'ops',
    keyAlias: 'kelola',
    tags: tags,
  );
}

void main() {
  test('tag env inherits; host env overrides; tags apply in name order', () {
    final resolved = resolveHostEnv(_host(['prod', 'edge']), [
      const EnvBinding(
        id: '1',
        scope: EnvScope.tag,
        scopeId: 'prod',
        name: 'REGION',
        value: 'from-prod',
      ),
      const EnvBinding(
        id: '2',
        scope: EnvScope.tag,
        scopeId: 'edge',
        name: 'REGION',
        value: 'from-edge',
      ),
      const EnvBinding(
        id: '3',
        scope: EnvScope.tag,
        scopeId: 'prod',
        name: 'ROLE',
        value: 'api',
      ),
      const EnvBinding(
        id: '4',
        scope: EnvScope.host,
        scopeId: 'h1',
        name: 'ROLE',
        value: 'worker',
      ),
      const EnvBinding(
        id: '5',
        scope: EnvScope.tag,
        scopeId: 'other',
        name: 'SKIP',
        value: 'no',
      ),
    ]);
    expect(resolved['REGION'], 'from-prod');
    expect(resolved['ROLE'], 'worker');
    expect(resolved.containsKey('SKIP'), isFalse);
  });

  test('invalid names are dropped and values are quoted into user commands', () {
    expect(isEnvName('FOO_1'), isTrue);
    expect(isEnvName('1FOO'), isFalse);
    expect(isEnvName('FOO-BAR'), isFalse);
    expect(
      prefixEnvExports('echo hi', const {'FOO': "a'b", 'bad-name': 'x'}),
      "export FOO='a'\\''b'; echo hi",
    );
    final probe = CommandRunnerProbe(
      'echo hi',
      env: const {'FOO': "a'b", 'bad-name': 'x'},
    );
    final cmd = probe.command(HostFacts.undiscovered);
    expect(cmd, startsWith('TERM=dumb /bin/sh -c '));
    expect(cmd, contains('export FOO='));
    expect(cmd, isNot(contains('bad-name')));
    expect(cmd, contains('echo hi'));

    final snippet = SnippetProbe(
      name: 'df',
      commandLine: 'df -PT',
      env: const {'ROLE': 'api'},
    );
    expect(snippet.command(HostFacts.undiscovered), contains('export ROLE='));
    expect(
      prefixEnvExports('df -PT', const {'ROLE': 'api'}),
      "export ROLE='api'; df -PT",
    );
  });
}
