import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/presentation/pro_locked_sheet.dart';
import 'package:kelola/presentation/screens/settings_screen.dart';

class _PricedEntitlement implements Entitlement {
  _PricedEntitlement({required this.priceLabel, this.paid = false});

  @override
  final String? priceLabel;
  bool paid;
  final _changes = StreamController<void>.broadcast();

  void unlock() {
    paid = true;
    _changes.add(null);
  }

  @override
  String get sourceLabel => 'std';

  @override
  bool isUnlocked(ProFeature feature) => paid;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  void initialize() {}

  @override
  Future<ProPurchaseResult> purchase() async => ProPurchaseResult.cancelled;

  @override
  Future<ProPurchaseResult> restore() async => ProPurchaseResult.unavailable;

  @override
  void dispose() {
    _changes.close();
  }
}

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    String? priceLabel,
    required Future<ProPurchaseResult> Function() onUnlock,
  }) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: ProLockedCard(
            title: 'Kelola Pro',
            body: 'Pro unlocks unlimited fleet.',
            priceLabel: priceLabel,
            onUnlock: onUnlock,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unlock button includes the store price', (tester) async {
    await pumpCard(
      tester,
      priceLabel: 'Rp 49.000',
      onUnlock: () async => ProPurchaseResult.cancelled,
    );
    expect(find.text('Unlock · Rp 49.000'), findsOneWidget);
  });

  testWidgets('unlock button has no price when the store has none', (
    tester,
  ) async {
    await pumpCard(tester, onUnlock: () async => ProPurchaseResult.cancelled);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.textContaining('Unlock ·'), findsNothing);
  });

  testWidgets('the button waits with a progress indicator', (tester) async {
    final gate = Completer<ProPurchaseResult>();
    await pumpCard(tester, onUnlock: () => gate.future);

    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    gate.complete(ProPurchaseResult.cancelled);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  Future<void> openSheet(WidgetTester tester, ProPurchaseResult result) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showProLockedSheet(
                  context,
                  title: 'Tunnels',
                  body: 'Locked.',
                  priceLabel: 'US\$4.99',
                  onPurchase: () async => result,
                ),
                child: const Text('locked'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('locked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock · US\$4.99'));
    await tester.pumpAndSettle();
  }

  testWidgets('pending purchase stays on the sheet', (tester) async {
    await openSheet(tester, ProPurchaseResult.pending);
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(
      find.text('Payment pending. Pro unlocks once Google Play confirms it.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed purchase stays on the sheet', (tester) async {
    await openSheet(tester, ProPurchaseResult.error);
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(find.text('Purchase did not complete. Try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an unavailable purchase stays on the sheet', (tester) async {
    await openSheet(tester, ProPurchaseResult.unavailable);
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(
      find.text('Purchases are not available on this device right now.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a cancelled purchase stays on the sheet with no message', (
    tester,
  ) async {
    await openSheet(tester, ProPurchaseResult.cancelled);
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(
      find.text('Payment pending. Pro unlocks once Google Play confirms it.'),
      findsNothing,
    );
    expect(find.text('Purchase did not complete. Try again.'), findsNothing);
    expect(
      find.text('Purchases are not available on this device right now.'),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a completed purchase closes the sheet', (tester) async {
    await openSheet(tester, ProPurchaseResult.purchased);
    expect(find.byType(KelolaSheet), findsNothing);
    expect(find.byType(ProLockedCard), findsNothing);
  });

  testWidgets('settings purchase row follows price and unlock', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final priced = _PricedEntitlement(priceLabel: 'Rp 49.000');
    addTearDown(priced.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entitlementProvider.overrideWithValue(priced)],
        child: const KelolaApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Pro · Rp 49.000'), findsOneWidget);

    await tester.tap(find.text('Free'));
    await tester.pumpAndSettle();
    expect(find.text('Kelola Pro'), findsWidgets);
    expect(find.text('Unlock · Rp 49.000'), findsOneWidget);
    expect(find.textContaining('unlimited fleet'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    priced.unlock();
    await tester.pumpAndSettle();

    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Kelola Pro'), findsOneWidget);
    expect(find.text('Free'), findsNothing);
  });

  testWidgets('a free row without a price does not open a purchase sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final free = _PricedEntitlement(priceLabel: null);
    addTearDown(free.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entitlementProvider.overrideWithValue(free)],
        child: const KelolaApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Free'), findsOneWidget);
    expect(find.text('purchase status'), findsOneWidget);

    await tester.tap(find.text('Free'));
    await tester.pumpAndSettle();
    expect(find.byType(ProLockedCard), findsNothing);
  });
}
