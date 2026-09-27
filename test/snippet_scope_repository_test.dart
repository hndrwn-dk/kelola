import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/snippets/snippet.dart';

void main() {
  test(
    'listSnippetsForHost hides other hosts and host delete drops scoped rows',
    () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      final east = await repo.insert(
        alias: 'east',
        address: '10.0.0.1',
        port: 22,
        username: 'hendr',
      );
      final west = await repo.insert(
        alias: 'west',
        address: '10.0.0.2',
        port: 22,
        username: 'hendr',
      );
      await repo.setHostTags(east.id, const ['prod']);
      final eastHost = (await repo.get(east.id))!;

      await repo.upsertSnippet(
        const Snippet(id: 'g', name: 'global', template: 'uptime'),
      );
      await repo.upsertSnippet(
        Snippet(
          id: 'e',
          name: 'east-only',
          template: 'uptime',
          hostId: east.id,
        ),
      );
      await repo.upsertSnippet(
        const Snippet(
          id: 'p',
          name: 'prod',
          template: 'uptime',
          tag: 'prod',
          startup: true,
        ),
      );

      final eastNames = (await repo.listSnippetsForHost(eastHost))
          .map((s) => s.name)
          .toSet();
      final westNames = (await repo.listSnippetsForHost(west))
          .map((s) => s.name)
          .toSet();
      expect(eastNames, containsAll(['global', 'east-only', 'prod']));
      expect(westNames, contains('global'));
      expect(westNames.contains('east-only'), isFalse);
      expect(westNames.contains('prod'), isFalse);

      await repo.delete(east.id);
      final leftover = await repo.listSnippets();
      expect(leftover.map((s) => s.id), containsAll(['g', 'p']));
      expect(leftover.any((s) => s.id == 'e'), isFalse);
    },
  );
}
