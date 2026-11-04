import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/presentation/whats_new_strings.dart';
import 'package:kelola/providers.dart';

class _UnlockedEntitlement implements Entitlement {
  @override
  String get sourceLabel => 'test';

  @override
  String? get priceLabel => null;

  @override
  bool isUnlocked(ProFeature feature) => true;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  void initialize() {}

  @override
  Future<ProPurchaseResult> purchase() async => ProPurchaseResult.unavailable;

  @override
  Future<ProPurchaseResult> restore() async => ProPurchaseResult.unavailable;

  @override
  void dispose() {}
}

const _label = "WHAT'S NEW · 1.1.0";

/// Onboarded upgrader on 1.0.0 with one failing host and a week of audit.
Future<HostRepository> _seed(KelolaDatabase db) async {
  final repo = HostRepository(db);
  await repo.saveDeviceKey(blobB64: 'AAAA', backend: 'strongbox');
  await repo.setSeenVersion('1.0.0');
  final nas = await repo.insert(
    alias: 'nas-01',
    address: '192.168.1.24',
    port: 22,
    username: 'hendra',
  );
  await repo.updateAttention(
    id: nas.id,
    attention: HostAttention.failedUnits,
    failedUnitCount: 2,
    diskRootPercent: 91,
    attentionAt: DateTime.now().toUtc(),
  );
  await repo.recordAudit(
    hostId: nas.id,
    hostAlias: 'nas-01',
    remoteUser: 'hendra',
    command: 'systemctl restart nginx',
    risk: 'mutate',
    usedSudo: true,
    title: 'Restart nginx',
    exitCode: 0,
  );
  return repo;
}

Widget _app(KelolaDatabase db, {String version = '1.1.0'}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    entitlementProvider.overrideWithValue(_UnlockedEntitlement()),
    appVersionProvider.overrideWithValue(version),
  ],
  child: const KelolaApp(),
);

Future<void> _teardown(WidgetTester tester, KelolaDatabase db) async {
  await db.close();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('upgrade shows the card above INSIGHTS AUDIT; Close hides it '
      'for good', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = await _seed(db);

    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.byType(WhatsNewCard), findsOneWidget);
    expect(find.text(_label), findsOneWidget);
    expect(find.text(WhatsNewStrings.title), findsOneWidget);
    expect(find.text(WhatsNewStrings.notes.first), findsOneWidget);
    expect(_top(tester, _label), lessThan(_top(tester, 'INSIGHTS AUDIT')));
    expect(
      _top(tester, 'INSIGHTS AUDIT'),
      lessThan(_top(tester, 'NEEDS ATTENTION')),
    );

    // Title is a heading; the card itself is not a tap target (no chevron).
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text(WhatsNewStrings.title)),
      matchesSemantics(label: WhatsNewStrings.title, isHeader: true),
    );
    handle.dispose();
    expect(
      find.descendant(
        of: find.byType(WhatsNewCard),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(WhatsNewCard),
        matching: find.byType(InkWell),
      ),
      findsOneWidget, // only the close button
    );

    final close = find.byTooltip(WhatsNewStrings.close);
    expect(close, findsOneWidget);
    final closeSize = tester.getSize(close);
    expect(closeSize.width, greaterThanOrEqualTo(48));
    expect(closeSize.height, greaterThanOrEqualTo(48));

    // Notes are human-written copy: body type, not mono.
    expect(
      tester.widget<Text>(find.text(WhatsNewStrings.notes.first)).style
          ?.fontFamily,
      'IBMPlexSans',
    );

    // Tapping the notes does nothing.
    await tester.tap(find.text(WhatsNewStrings.notes.first));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewCard), findsOneWidget);

    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(find.byType(WhatsNewCard), findsNothing);
    expect(find.text(_label), findsNothing);
    expect(
      _top(tester, 'INSIGHTS AUDIT'),
      lessThan(_top(tester, 'NEEDS ATTENTION')),
    );
    expect(find.text('nas-01'), findsOneWidget);
    expect(find.byType(HostsUtilityRail), findsOneWidget);
    expect(await repo.seenVersion(), '1.1.0');
    expect(await HostRepository(db).seenVersion(), '1.1.0');

    // Restart on the same version: fresh providers read storage again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();
    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.byType(WhatsNewCard), findsNothing);
    expect(find.text('INSIGHTS AUDIT'), findsOneWidget);

    await _teardown(tester, db);
  });

  testWidgets('no card without a release version (debug / flutter run)', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await _seed(db);

    await tester.pumpWidget(_app(db, version: ''));
    await tester.pumpAndSettle();

    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.byType(WhatsNewCard), findsNothing);
    expect(find.text('INSIGHTS AUDIT'), findsOneWidget);
    await _teardown(tester, db);
  });

  // The Hosts header (HostsRootBar) already overflows at 2.0 with or
  // without the card, so the card is checked on its own, as it renders in
  // the Hosts list: dark theme, phone widths, ambient text scale 2.0.
  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('card does not overflow at text scale 2.0 in dark mode '
        '(${width.toInt()}dp)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildKelolaDarkTheme(),
          home: Scaffold(
            // Background arcs behind the card, as on Hosts.
            body: Stack(
              children: [
                const Positioned.fill(child: HostsChromeAccent()),
                ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    WhatsNewCard(
                      label: WhatsNewStrings.label('1.1.0'),
                      title: WhatsNewStrings.title,
                      notes: WhatsNewStrings.notes,
                      closeTooltip: WhatsNewStrings.close,
                      onClose: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final card = tester.element(find.byType(WhatsNewCard));
      expect(Theme.of(card).brightness, Brightness.dark);
      expect(MediaQuery.textScalerOf(card).scale(10), 20);
      for (final note in WhatsNewStrings.notes) {
        expect(find.text(note), findsOneWidget);
      }
      expect(find.byTooltip(WhatsNewStrings.close), findsOneWidget);
    });
  }

  testWidgets('NEEDS ATTENTION stays on the first screen of a normal phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400); // 360 x 800 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await _seed(db);

    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    expect(find.byType(WhatsNewCard), findsOneWidget);
    // Upper two thirds; the test font wraps body copy wider than a device.
    expect(_top(tester, 'NEEDS ATTENTION'), lessThan(800 * 0.65));
    expect(tester.getBottomLeft(find.text('nas-01')).dy, lessThan(800));
    await _teardown(tester, db);
  });
}
