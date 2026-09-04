import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/llm/provider.dart';

void main() {
  test('fresh install LLM provider defaults to none', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final settings = await repo.loadLlmSettings();
    expect(settings.provider, LlmProvider.none);
    expect(settings.baseUrl, isNull);
    expect(settings.apiKey, isNull);
  });
}
