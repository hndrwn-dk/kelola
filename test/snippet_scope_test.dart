import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/snippets/snippet_scope.dart';

const _east = Host(
  id: 'h-east',
  alias: 'east-worker',
  address: '10.0.0.1',
  port: 22,
  username: 'hendr',
  keyAlias: 'kelola',
  tags: ['prod'],
);

const _west = Host(
  id: 'h-west',
  alias: 'west-worker',
  address: '10.0.0.2',
  port: 22,
  username: 'hendr',
  keyAlias: 'kelola',
  tags: ['lab'],
);

void main() {
  const global = Snippet(id: 'g', name: 'df', template: 'df -PT');
  const forEast = Snippet(
    id: 'e',
    name: 'east-only',
    template: 'uptime',
    hostId: 'h-east',
  );
  const prodTag = Snippet(
    id: 'p',
    name: 'prod',
    template: 'uptime',
    tag: 'prod',
    startup: true,
  );

  test('global snippets apply everywhere; host and tag scopes isolate', () {
    expect(snippetAppliesToHost(global, _east), isTrue);
    expect(snippetAppliesToHost(global, _west), isTrue);
    expect(snippetAppliesToHost(forEast, _east), isTrue);
    expect(snippetAppliesToHost(forEast, _west), isFalse);
    expect(snippetAppliesToHost(prodTag, _east), isTrue);
    expect(snippetAppliesToHost(prodTag, _west), isFalse);
  });

  test('hostId wins over tag and startup is an offer list', () {
    const both = Snippet(
      id: 'b',
      name: 'both',
      template: 'uptime',
      hostId: 'h-west',
      tag: 'prod',
      startup: true,
    );
    expect(snippetAppliesToHost(both, _west), isTrue);
    expect(snippetAppliesToHost(both, _east), isFalse);
    expect(startupSnippetsForHost([global, forEast, prodTag, both], _east), [
      prodTag,
    ]);
    expect(startupSnippetsForHost([global, forEast, prodTag, both], _west), [
      both,
    ]);
  });
}
