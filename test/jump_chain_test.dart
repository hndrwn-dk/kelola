import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/jump_chain.dart';

Host _h(String id, {String? jump}) {
  return Host(
    id: id,
    alias: id,
    address: '$id.example',
    port: 22,
    username: 'ops',
    keyAlias: 'kelola',
    jumpHostId: jump,
  );
}

void main() {
  test('direct host has no via label', () {
    final web = _h('web');
    final chain = resolveJumpChain(web, {'web': web});
    expect(chain.kind, JumpChainKind.ok);
    expect(chain.hops, isEmpty);
    expect(jumpViaLabel(web, {'web': web}), isNull);
    expect(appendVia('10.0.0.8', null), '10.0.0.8');
  });

  test('two-hop chain is outermost first', () {
    final edge = _h('edge');
    final inner = _h('inner', jump: 'edge');
    final web = _h('web', jump: 'inner');
    final byId = {'edge': edge, 'inner': inner, 'web': web};

    final chain = resolveJumpChain(web, byId);
    expect(chain.kind, JumpChainKind.ok);
    expect(chain.hops.map((h) => h.alias), ['edge', 'inner']);
    expect(jumpViaLabel(web, byId), 'via edge · inner');
    expect(appendVia('10.0.0.8', jumpViaLabel(web, byId)),
        '10.0.0.8 · via edge · inner');
  });

  test('cycle and missing hop are distinct failures', () {
    final a = _h('a', jump: 'b');
    final b = _h('b', jump: 'a');
    expect(resolveJumpChain(a, {'a': a, 'b': b}).kind, JumpChainKind.cycle);
    expect(wouldCycle('a', 'b', {'a': a, 'b': b}), isTrue);

    final web = _h('web', jump: 'gone');
    expect(resolveJumpChain(web, {'web': web}).kind, JumpChainKind.missing);
    expect(wouldCycle('web', 'gone', {'web': web}), isFalse);
  });

  test('proposed jump that points back at the dest is a cycle', () {
    final edge = _h('edge');
    final web = _h('web');
    final byId = {'edge': edge, 'web': web};
    expect(wouldCycle('web', 'edge', byId), isFalse);

    final edged = _h('edge', jump: 'web');
    expect(wouldCycle('web', 'edge', {'edge': edged, 'web': web}), isTrue);
    expect(wouldCycle('web', 'web', byId), isTrue);
  });

  test('chain longer than kMaxJumpHops is too long', () {
    final byId = <String, Host>{};
    Host? prev;
    for (var i = 0; i <= kMaxJumpHops; i++) {
      final id = 'h$i';
      final hop = _h(id, jump: prev?.id);
      byId[id] = hop;
      prev = hop;
    }
    final dest = _h('dest', jump: prev!.id);
    byId['dest'] = dest;
    expect(resolveJumpChain(dest, byId).kind, JumpChainKind.tooLong);
  });
}
