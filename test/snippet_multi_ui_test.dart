import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/screens/snippets_screen.dart';
import 'package:kelola/providers.dart';

const _host = Host(
  id: 'h1',
  alias: 'nas-01',
  address: '10.0.0.8',
  port: 22,
  username: 'ops',
  keyAlias: 'kelola',
);

class _Entitlement implements Entitlement {
  _Entitlement({required this.unlocked});

  final bool unlocked;

  @override
  String get sourceLabel => 'test';

  @override
  bool isUnlocked(ProFeature feature) => unlocked;

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
  late KelolaDatabase db;
  late HostRepository hosts;

  setUp(() {
    db = KelolaDatabase.memory();
    hosts = HostRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedHosts() async {
    await hosts.listSnippets();
    await hosts.insert(
      alias: 'nas-01',
      address: '10.0.0.8',
      port: 22,
      username: 'ops',
    );
    await hosts.insert(
      alias: 'edge-01',
      address: '10.0.0.9',
      port: 22,
      username: 'ops',
    );
  }

  Future<void> pump(WidgetTester tester, {required bool unlocked}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(hosts),
          entitlementProvider.overrideWithValue(_Entitlement(unlocked: unlocked)),
        ],
        child: const KelolaApp(
          home: SnippetsScreen(host: _host),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Run on hosts is locked until snippetMulti is unlocked', (
    tester,
  ) async {
    await seedHosts();
    await pump(tester, unlocked: false);
    await tester.tap(find.text('df -PT'));
    await tester.pumpAndSettle();
    expect(find.text('Run on hosts'), findsOneWidget);
    await tester.tap(find.text('Run on hosts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This build keeps multi-exec locked'), findsOneWidget);
  });

  testWidgets('unlocked Run on hosts previews the resolved command per host', (
    tester,
  ) async {
    await seedHosts();
    await pump(tester, unlocked: true);
    await tester.tap(find.text('df -PT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run on hosts'));
    await tester.pumpAndSettle();
    expect(find.text('nas-01'), findsWidgets);
    expect(find.text('edge-01'), findsWidgets);
    expect(find.textContaining('df -PT'), findsWidgets);
  });
}
