import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/app_lock/app_lock_port.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/app_lock/app_lock_timeout.dart';
import 'package:kelola/presentation/screens/settings_screen.dart';
import 'package:kelola/providers.dart';

class _FakePort implements AppLockPort {
  bool available = true;
  bool unlock = false;
  int authenticates = 0;
  bool? secure;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<bool> authenticate() async {
    authenticates++;
    return unlock;
  }

  @override
  Future<void> setRecentsSecure(bool value) async {
    secure = value;
  }
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test('queued warm links keep only the last uri', () {
    final queue = AppLockLinkQueue();
    queue.enqueue('kelola://host/a');
    queue.enqueue('kelola://host/b');
    expect(queue.take(), 'kelola://host/b');
    expect(queue.take(), isNull);
  });

  testWidgets('default off shows hosts and does not lock', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await HostRepository(db).insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendr',
    );
    final port = _FakePort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appLockPortProvider.overrideWithValue(port),
        ],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('nas-01'), findsOneWidget);
    expect(find.text('Unlock to open the inventory'), findsNothing);
    expect(port.secure, isNot(true));
    await _flush(tester);
  });

  testWidgets('cold start with lock on hides aliases until unlock', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendr',
    );
    await repo.setAppLockTimeoutSec(AppLockTimeout.immediately.seconds);
    final port = _FakePort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appLockPortProvider.overrideWithValue(port),
        ],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unlock to open the inventory'), findsOneWidget);
    expect(find.text('nas-01'), findsNothing);
    expect(port.secure, isTrue);
    expect(port.authenticates, greaterThan(0));

    port.unlock = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('nas-01'), findsOneWidget);
    expect(find.text('Unlock to open the inventory'), findsNothing);

    port.unlock = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('nas-01'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Unlock to open the inventory'), findsOneWidget);
    expect(find.text('nas-01'), findsNothing);
    await _flush(tester);
  });

  testWidgets('settings lists timeouts; no device lock disables the row', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final port = _FakePort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appLockPortProvider.overrideWithValue(port),
        ],
        child: const KelolaApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.text('App lock'));
    await tester.pumpAndSettle();
    expect(find.text('Immediately'), findsOneWidget);
    expect(find.text('1 minute'), findsOneWidget);
    expect(find.text('5 minutes'), findsOneWidget);
    expect(find.text('15 minutes'), findsOneWidget);

    await tester.tap(find.text('Immediately'));
    await tester.pumpAndSettle();
    expect(await HostRepository(db).appLockTimeoutSec(), -1);
    expect(find.text('Immediately'), findsOneWidget);
    await _flush(tester);
  });

  testWidgets('no device lock disables the app lock row', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final port = _FakePort()..available = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appLockPortProvider.overrideWithValue(port),
        ],
        child: const KelolaApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('set a device screen lock first'), findsOneWidget);
    await tester.tap(find.text('App lock'));
    await tester.pumpAndSettle();
    expect(find.text('1 minute'), findsNothing);
    await _flush(tester);
  });
}
