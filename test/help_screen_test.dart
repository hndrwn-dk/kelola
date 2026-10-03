import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/support/support_links.dart';
import 'package:kelola/presentation/screens/help_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  testWidgets('Help lists every FAQ question and answer', (tester) async {
    // KelolaApp's FleetWatchResume reads providers on the first frame.
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(home: HelpScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Help'), findsOneWidget);
    expect(find.byType(HelpTopic), findsNWidgets(kSupportFaq.length));
    for (final item in kSupportFaq) {
      expect(find.text(item.question), findsOneWidget);
      expect(find.text(item.answer), findsOneWidget);
    }
  });
}
