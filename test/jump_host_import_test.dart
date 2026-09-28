import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  test('import wires last hop and newly created intermediates', () async {
    const source = '''
Host edge
  HostName 1.2.3.4
  User ops

Host inner
  HostName 10.0.0.2
  User ops

Host web
  HostName 10.0.0.10
  User deploy
  ProxyJump edge,inner
''';
    expect(await repo.importSshConfig(source), 3);
    final byAlias = {for (final h in await repo.list()) h.alias: h};
    expect(byAlias['web']!.jumpHostId, byAlias['inner']!.id);
    expect(byAlias['inner']!.jumpHostId, byAlias['edge']!.id);
    expect(byAlias['edge']!.jumpHostId, isNull);
  });

  test('import does not rewrite jump on an existing hop host', () async {
    final existingInner = await repo.insert(
      alias: 'inner',
      address: '10.0.0.2',
      port: 22,
      username: 'ops',
    );
    await repo.importSshConfig('''
Host edge
  HostName 1.2.3.4
  User ops

Host web
  HostName 10.0.0.10
  User deploy
  ProxyJump edge,inner
''');
    final inner = (await repo.get(existingInner.id))!;
    expect(inner.jumpHostId, isNull);
    final byAlias = {for (final h in await repo.list()) h.alias: h};
    expect(byAlias['web']!.jumpHostId, existingInner.id);
  });
}
