import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  testWidgets('hosts empty state invites the next action', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.textContaining('Add your first server'), findsOneWidget);
  });
}
