import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/host_env/host_env.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_tags.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/snippets/snippet_scope.dart';

Host _host(List<String> tags) => Host(
      id: 'h',
      alias: 'h',
      address: '10.0.0.1',
      port: 22,
      username: 'u',
      keyAlias: 'k',
      tags: tags,
    );

void main() {
  test('typed tags split, lowercase and drop repeats', () {
    expect(parseHostTags('UAT, edge;  uat\nprod,'), ['uat', 'edge', 'prod']);
    expect(parseHostTags('   '), isEmpty);
  });

  test('tapping a tag adds it, and tapping again removes it', () {
    expect(toggleHostTag('uat', 'prod'), 'uat, prod');
    expect(toggleHostTag('uat, prod', 'prod'), 'uat');
    expect(toggleHostTag('', 'prod'), 'prod');
    expect(toggleHostTag('UAT', 'uat'), '');
  });

  test('known tags are distinct and sorted', () {
    expect(
      knownHostTags([
        _host(['uat', 'edge']),
        _host(['uat']),
        _host(const []),
      ]),
      ['edge', 'uat'],
    );
  });

  test('a snippet tagged in capitals still finds its hosts', () {
    const snippet = Snippet(id: 's', name: 's', template: 'x', tag: 'UAT');
    expect(snippetAppliesToHost(snippet, _host(['uat'])), isTrue);
    expect(snippetAppliesToHost(snippet, _host(['prod'])), isFalse);
  });

  test('a variable tagged in capitals still reaches its hosts', () {
    const binding = EnvBinding(
      id: 'e',
      scope: EnvScope.tag,
      scopeId: 'UAT',
      name: 'REGION',
      value: 'east',
    );
    expect(resolveHostEnv(_host(['uat']), [binding]), {'REGION': 'east'});
  });
}
