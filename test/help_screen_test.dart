import 'package:flutter/material.dart';
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
    // The list is lazy: a tall view builds every topic (taller since the
    // Service lenses answer has paragraph breaks).
    tester.view.physicalSize = const Size(1080, 16000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

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

  test('Service lenses topic explains the grant without a sudo group', () {
    final matches =
        kSupportFaq.where((item) => item.question == 'Service lenses');
    expect(matches, hasLength(1));
    final answer = matches.single.answer;
    expect(answer, contains('kelola-web'));
    expect(answer, isNot(contains('sudo group')));
    // Short paragraphs (HelpTopic is one Text, so a blank line separates).
    final paragraphs = answer.split('\n\n');
    expect(paragraphs.length, greaterThanOrEqualTo(4));
    for (final p in paragraphs) {
      expect(p.trim(), isNotEmpty);
      expect(p.length, lessThan(500), reason: p);
    }
    expect(answer, contains('not root-owned, or that others can write'));
  });
}
