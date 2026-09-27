import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/snippets/snippet_multi.dart';

Host _host(String id, {List<String> tags = const [], bool readOnly = false}) {
  return Host(
    id: id,
    alias: id,
    address: '10.0.0.$id',
    port: 22,
    username: 'ops',
    keyAlias: 'kelola',
    readOnly: readOnly,
    tags: tags,
  );
}

void main() {
  const snippet = Snippet(
    id: 's1',
    name: 'echo-host',
    template: 'echo {{host}}',
  );

  test('plan uses snippet scope and does not invent hosts', () {
    final tagged = Snippet(
      id: 's2',
      name: 'tag',
      template: 'uptime',
      tag: 'edge',
    );
    final hosts = [_host('a', tags: ['edge']), _host('b'), _host('c', tags: ['edge'])];
    expect(planSnippetMultiHosts(snippet, hosts).map((h) => h.id), ['a', 'b', 'c']);
    expect(planSnippetMultiHosts(tagged, hosts).map((h) => h.id), ['a', 'c']);
    expect(
      planSnippetMultiHosts(
        const Snippet(id: 's3', name: 'one', template: 'uptime', hostId: 'b'),
        hosts,
      ).map((h) => h.id),
      ['b'],
    );
  });

  test('preview binds host alias per target and keeps shared placeholders', () {
    const unitSnippet = Snippet(
      id: 's4',
      name: 'status',
      template: 'systemctl status {{unit}} --no-pager && echo {{host}}',
    );
    final previews = previewSnippetMulti(
      snippet: unitSnippet,
      hosts: [_host('web'), _host('db')],
      shared: const SnippetBindings(unit: 'nginx.service'),
    );
    expect(previews.map((p) => p.host.id), ['web', 'db']);
    expect(previews.first.commandLine, contains('nginx.service'));
    expect(previews.first.commandLine, contains('web'));
    expect(previews.last.commandLine, contains('db'));
    expect(previews.last.commandLine, isNot(contains('web')));
    expect(
      previewSnippetMulti(
        snippet: unitSnippet,
        hosts: [_host('web')],
        shared: const SnippetBindings(),
      ).single.commandLine,
      isNull,
    );
  });

  test('multi-exec is sequential host scope and never fleet', () async {
    final executed = <String>[];
    final outcomes = await runSnippetMulti(
      snippet: snippet,
      hosts: [_host('a'), _host('b')],
      shared: const SnippetBindings(),
      execute: <T>(host, probe) async {
        executed.add(host.id);
        return CommandRunnerResult(
              stdout: host.alias,
              stderr: '',
              exitCode: 0,
            )
            as T;
      },
      confirm: (host, probe) async => true,
    );
    expect(executed, ['a', 'b']);
    expect(outcomes.map((o) => o.hostId), ['a', 'b']);
    expect(outcomes.every((o) => o.status == SnippetMultiStatus.ran), isTrue);
  });

  test('skip and failure on one host do not abort the rest', () async {
    final outcomes = await runSnippetMulti(
      snippet: const Snippet(
        id: 's5',
        name: 'reboot',
        template: 'reboot',
      ),
      hosts: [_host('a'), _host('b'), _host('c')],
      shared: const SnippetBindings(),
      execute: <T>(host, probe) async {
        if (host.id == 'c') {
          throw StateError('ssh down');
        }
        return CommandRunnerResult(stdout: '', stderr: '', exitCode: 0) as T;
      },
      confirm: (host, probe) async => host.id != 'b',
    );
    expect(outcomes.map((o) => o.status), [
      SnippetMultiStatus.ran,
      SnippetMultiStatus.skipped,
      SnippetMultiStatus.failed,
    ]);
  });

  test('multi-exec source stays off the fleet path', () {
    final src = File('lib/domain/snippets/snippet_multi.dart').readAsStringSync();
    expect(src, contains('runSnippet'));
    expect(src, contains('ProbeScope.host'));
    expect(src, isNot(contains('ProbeScope.fleet')));
    expect(src, isNot(contains('dartssh2')));
    expect(src, isNot(contains('entitlement')));
    expect(src, isNot(contains('assertFleetReadOnly')));
  });
}
