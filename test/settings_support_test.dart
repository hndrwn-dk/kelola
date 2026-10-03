import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/support/support_links.dart';
import 'package:kelola/presentation/screens/help_screen.dart';
import 'package:kelola/presentation/screens/settings_screen.dart';

class _FakeEntitlement implements Entitlement {
  @override
  String get sourceLabel => 'std';

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

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    SettingsLaunchUrl? launchUrlFn,
    SettingsShare? shareFn,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [entitlementProvider.overrideWithValue(_FakeEntitlement())],
        child: KelolaApp(
          home: SettingsScreen(launchUrlFn: launchUrlFn, shareFn: shareFn),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Support tray lists help, legal, review, and share', (
    tester,
  ) async {
    await pumpSettings(tester);
    // SectionSlab uppercases HostGroupTray labels.
    expect(find.text('SUPPORT'), findsOneWidget);
    expect(find.text('Help & FAQ'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Rate & review'), findsOneWidget);
    expect(find.text('Share Kelola'), findsOneWidget);
  });

  testWidgets('Help & FAQ pushes the Help screen', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Help & FAQ'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.text('How do I add a server?'), findsOneWidget);
  });

  testWidgets('Privacy, Terms, and Rate & review open the canonical URLs', (
    tester,
  ) async {
    final opened = <Uri>[];
    await pumpSettings(
      tester,
      launchUrlFn: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terms of Service'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rate & review'));
    await tester.pumpAndSettle();

    expect(opened.map((u) => u.toString()).toList(), [
      kKelolaPrivacyUrl,
      kKelolaTermsUrl,
      kKelolaPlayStoreUrl,
    ]);
  });

  testWidgets('Share Kelola shares the Play listing text', (tester) async {
    String? shared;
    String? sharedSubject;
    await pumpSettings(
      tester,
      shareFn: (text, {subject}) async {
        shared = text;
        sharedSubject = subject;
      },
    );
    await tester.ensureVisible(find.text('Share Kelola'));
    await tester.tap(find.text('Share Kelola'));
    await tester.pumpAndSettle();
    expect(shared, kKelolaShareText);
    expect(sharedSubject, kKelolaShareSubject);
  });

  testWidgets('failed launch shows Could not open link', (tester) async {
    await pumpSettings(tester, launchUrlFn: (uri) async => false);
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open link.'), findsOneWidget);
  });

  testWidgets('failed share shows Could not share', (tester) async {
    await pumpSettings(
      tester,
      shareFn: (text, {subject}) async {
        throw Exception('share failed');
      },
    );
    await tester.ensureVisible(find.text('Share Kelola'));
    await tester.tap(find.text('Share Kelola'));
    await tester.pumpAndSettle();
    expect(find.text('Could not share.'), findsOneWidget);
  });
}
