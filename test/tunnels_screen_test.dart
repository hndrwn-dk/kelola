import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/data/ssh/tunnel_bridge.dart';
import 'package:kelola/data/ssh/tunnel_manager.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_close_reason.dart';
import 'package:kelola/domain/tunnels/tunnel_presets.dart';
import 'package:kelola/domain/tunnels/tunnel_validation.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/presentation/screens/tunnels_screen.dart';
import 'package:kelola/providers.dart';

class FakeTunnelBridge implements TunnelBridge {
  bool? lastPostNotificationsResult = true;
  int requestPostNotificationsCalls = 0;
  int openNotificationSettingsCalls = 0;

  @override
  Future<void> start({required String text}) async {}

  @override
  Future<void> update({required String text}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<bool> requestPostNotifications() async {
    requestPostNotificationsCalls++;
    return lastPostNotificationsResult ?? true;
  }

  @override
  Future<void> openNotificationSettings() async {
    openNotificationSettingsCalls++;
  }

  @override
  void setNativeHandler(TunnelNativeHandler? handler) {}
}

class FakeTunnelSessionApi implements TunnelSessionApi {
  FakeTunnelSessionApi([List<ActiveTunnel> initial = const []])
      : _tunnels = List.of(initial);

  final List<ActiveTunnel> _tunnels;
  final _controller = StreamController<List<ActiveTunnel>>.broadcast();
  final retried = <String>[];
  final dismissed = <String>[];
  final closed = <String>[];
  final opened = <TunnelTarget>[];

  @override
  Stream<List<ActiveTunnel>> watch() async* {
    yield List.unmodifiable(_tunnels);
    yield* _controller.stream;
  }

  void emit(List<ActiveTunnel> next) {
    _tunnels
      ..clear()
      ..addAll(next);
    _controller.add(List.unmodifiable(_tunnels));
  }

  @override
  Future<ActiveTunnel> open(
    TunnelTarget target, {
    required String hostAlias,
  }) async {
    opened.add(target);
    final tunnel = ActiveTunnel(
      id: 'open-${opened.length}',
      target: target,
      hostAlias: hostAlias,
      localPort: 4000 + opened.length,
      state: TunnelState.listening,
      openedAtUtc: DateTime.utc(2026, 9, 13, 12),
      openChannels: 0,
      closesAtUtc: DateTime.utc(2026, 9, 13, 12, 10),
    );
    _tunnels.add(tunnel);
    _controller.add(List.unmodifiable(_tunnels));
    return tunnel;
  }

  @override
  Future<void> close(
    String tunnelId, {
    TunnelCloseReason reason = TunnelCloseReason.user,
  }) async {
    closed.add(tunnelId);
    _tunnels.removeWhere((t) => t.id == tunnelId);
    _controller.add(List.unmodifiable(_tunnels));
  }

  @override
  Future<void> closeAll({
    TunnelCloseReason reason = TunnelCloseReason.termination,
  }) async {
    final ids = _tunnels.map((t) => t.id).toList(growable: false);
    for (final id in ids) {
      await close(id, reason: reason);
    }
  }

  @override
  void dismissFailed(String tunnelId) {
    dismissed.add(tunnelId);
    _tunnels.removeWhere((t) => t.id == tunnelId);
    _controller.add(List.unmodifiable(_tunnels));
  }

  @override
  Future<ActiveTunnel> retry(String tunnelId) async {
    retried.add(tunnelId);
    final failed = _tunnels.firstWhere((t) => t.id == tunnelId);
    _tunnels.removeWhere((t) => t.id == tunnelId);
    return open(failed.target, hostAlias: failed.hostAlias);
  }

  Future<void> dispose() => _controller.close();
}

TunnelTarget _target({
  String id = 't1',
  String hostId = 'h1',
  String label = 'Cockpit',
  TunnelScheme scheme = TunnelScheme.https,
  int port = 9090,
}) {
  return TunnelTarget(
    id: id,
    hostId: hostId,
    label: label,
    remoteHost: '127.0.0.1',
    remotePort: port,
    scheme: scheme,
    path: '/',
  );
}

ActiveTunnel _tunnel({
  required String id,
  required TunnelTarget target,
  required String hostAlias,
  required TunnelState state,
  int localPort = 4242,
  int openChannels = 0,
  DateTime? closesAtUtc,
  String? errorSummary,
}) {
  return ActiveTunnel(
    id: id,
    target: target,
    hostAlias: hostAlias,
    localPort: localPort,
    state: state,
    openedAtUtc: DateTime.utc(2026, 9, 13, 11, 50),
    openChannels: openChannels,
    closesAtUtc: closesAtUtc,
    errorSummary: errorSummary,
  );
}

void main() {
  late KelolaDatabase db;
  late HostRepository hosts;
  late TunnelRepository tunnels;
  late FakeTunnelSessionApi fakeManager;
  late FakeTunnelBridge fakeBridge;

  setUp(() {
    db = KelolaDatabase.memory();
    hosts = HostRepository(db);
    tunnels = TunnelRepository(db);
    fakeManager = FakeTunnelSessionApi();
    fakeBridge = FakeTunnelBridge();
  });

  tearDown(() async {
    await fakeManager.dispose();
    await db.close();
  });

  Future<String> seedHost({String alias = 'web-01'}) async {
    final host = await hosts.insert(
      alias: alias,
      address: '192.168.1.10',
      port: 22,
      username: 'ops',
    );
    return host.id;
  }

  List<Override> overrides({
    Entitlement entitlement = const OpenEntitlement(),
    FakeTunnelSessionApi? manager,
    FakeTunnelBridge? bridge,
  }) {
    return [
      databaseProvider.overrideWithValue(db),
      hostRepositoryProvider.overrideWithValue(hosts),
      tunnelRepositoryProvider.overrideWithValue(tunnels),
      tunnelManagerProvider.overrideWithValue(manager ?? fakeManager),
      tunnelBridgeProvider.overrideWithValue(bridge ?? fakeBridge),
      entitlementProvider.overrideWithValue(entitlement),
    ];
  }

  Future<void> pumpTunnels(
    WidgetTester tester, {
    required String hostId,
    DateTime Function()? clock,
    bool? notificationsAllowed,
    List<TunnelTarget> targets = const [],
    List<Override>? extraOverrides,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          tunnelTargetsProvider(hostId)
              .overrideWith((ref) => Stream.value(targets)),
          ...?extraOverrides,
        ],
        child: KelolaApp(
          home: TunnelsScreen(
            hostId: hostId,
            clock: clock ?? () => DateTime.utc(2026, 9, 13, 12),
            initialNotificationsAllowed: notificationsAllowed,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  test('idle countdown formats m:ss from closesAtUtc', () {
    expect(
      tunnelIdleCountdownLabel(
        DateTime.utc(2026, 9, 13, 12, 1, 0),
        DateTime.utc(2026, 9, 13, 12, 0, 13),
      ),
      'closing in 0:47',
    );
  });

  testWidgets('chips show All / This host / Failed counts', (tester) async {
    final hostId = await seedHost();
    final other = _target(id: 't2', hostId: 'h2', label: 'Grafana', scheme: TunnelScheme.http, port: 3000);
    fakeManager.emit([
      _tunnel(
        id: 'a',
        target: _target(hostId: hostId),
        hostAlias: 'web-01',
        state: TunnelState.listening,
      ),
      _tunnel(
        id: 'b',
        target: other,
        hostAlias: 'db-02',
        state: TunnelState.failed,
        errorSummary: 'refused',
      ),
      _tunnel(
        id: 'c',
        target: _target(id: 't3', hostId: hostId, label: 'Prometheus', scheme: TunnelScheme.http),
        hostAlias: 'web-01',
        state: TunnelState.failed,
        errorSummary: 'timeout',
      ),
    ]);

    await pumpTunnels(tester, hostId: hostId);

    expect(find.widgetWithText(FilterPill, 'ALL 3'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'THIS HOST 2'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'FAILED 2'), findsOneWidget);
  });

  testWidgets('empty states for saved targets and filtered active list',
      (tester) async {
    final hostId = await seedHost();
    await pumpTunnels(tester, hostId: hostId);

    expect(find.textContaining('No saved targets'), findsOneWidget);
    expect(find.textContaining('No active tunnels'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterPill, 'FAILED 0'));
    await tester.pump();
    expect(find.textContaining('No failed tunnels'), findsOneWidget);
  });

  testWidgets('idleClosing row shows countdown from closesAtUtc', (tester) async {
    final hostId = await seedHost();
    fakeManager.emit([
      _tunnel(
        id: 'a',
        target: _target(hostId: hostId),
        hostAlias: 'web-01',
        state: TunnelState.idleClosing,
        closesAtUtc: DateTime.utc(2026, 9, 13, 12, 1, 0),
      ),
    ]);

    await pumpTunnels(
      tester,
      hostId: hostId,
      clock: () => DateTime.utc(2026, 9, 13, 12, 0, 13),
    );

    expect(find.textContaining('closing in 0:47'), findsOneWidget);
  });

  testWidgets('failed rows expose Retry and Dismiss', (tester) async {
    final hostId = await seedHost();
    fakeManager.emit([
      _tunnel(
        id: 'fail-1',
        target: _target(hostId: hostId),
        hostAlias: 'web-01',
        state: TunnelState.failed,
        errorSummary: 'connection refused',
      ),
    ]);

    await pumpTunnels(tester, hostId: hostId);
    await tester.tap(find.widgetWithText(FilterPill, 'FAILED 1'));
    await tester.pump();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(fakeManager.retried, ['fail-1']);

    fakeManager.emit([
      _tunnel(
        id: 'fail-2',
        target: _target(hostId: hostId),
        hostAlias: 'web-01',
        state: TunnelState.failed,
        errorSummary: 'again',
      ),
    ]);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterPill, 'FAILED 1'));
    await tester.pump();
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(fakeManager.dismissed, ['fail-2']);
  });

  testWidgets('Start requests post notifications once and opens tunnel',
      (tester) async {
    final hostId = await seedHost();
    final target = _target(hostId: hostId);

    await pumpTunnels(tester, hostId: hostId, targets: [target]);
    expect(find.text('Cockpit'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();

    expect(fakeBridge.requestPostNotificationsCalls, 1);
    expect(fakeManager.opened, [target]);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(fakeBridge.requestPostNotificationsCalls, 1);
  });

  testWidgets('notification denied shows settings deep link', (tester) async {
    final hostId = await seedHost();
    await pumpTunnels(
      tester,
      hostId: hostId,
      notificationsAllowed: false,
    );

    expect(find.textContaining('Notifications are off'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(fakeBridge.openNotificationSettingsCalls, 1);
  });

  testWidgets('HTTP open shows plaintext warning; HTTPS shows cert note',
      (tester) async {
    final hostId = await seedHost();
    final httpTarget = _target(
      id: 'http',
      hostId: hostId,
      label: 'Grafana',
      scheme: TunnelScheme.http,
      port: 3000,
    );
    final httpsTarget = _target(
      id: 'https',
      hostId: hostId,
      label: 'Cockpit',
      scheme: TunnelScheme.https,
    );
    Uri? launched;
    fakeManager.emit([
      _tunnel(
        id: 'http-1',
        target: httpTarget,
        hostAlias: 'web-01',
        state: TunnelState.listening,
        localPort: 5001,
      ),
      _tunnel(
        id: 'https-1',
        target: httpsTarget,
        hostAlias: 'web-01',
        state: TunnelState.listening,
        localPort: 5002,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          tunnelTargetsProvider(hostId)
              .overrideWith((ref) => Stream.value(const <TunnelTarget>[])),
        ],
        child: KelolaApp(
          home: TunnelsScreen(
            hostId: hostId,
            clock: () => DateTime.utc(2026, 9, 13, 12),
            launchUrlFn: (uri) async {
              launched = uri;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });

    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('plaintext on this device'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(launched, Uri.parse('http://127.0.0.1:5001/'));

    await tester.tap(find.text('Open').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining("certificate doesn't match 127.0.0.1"),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(launched, Uri.parse('https://127.0.0.1:5002/'));
  });

  testWidgets('Stop uses MutateConfirmDialog, not DestructiveConfirmSheet',
      (tester) async {
    final hostId = await seedHost();
    fakeManager.emit([
      _tunnel(
        id: 'live',
        target: _target(hostId: hostId),
        hostAlias: 'web-01',
        state: TunnelState.listening,
      ),
    ]);

    await pumpTunnels(tester, hostId: hostId);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(find.byType(DestructiveConfirmSheet), findsNothing);
    expect(find.byType(MutateConfirmDialog), findsOneWidget);

    await tester.tap(find.text('Stop tunnel'));
    await tester.pumpAndSettle();
    expect(fakeManager.closed, ['live']);
  });

  testWidgets('locked explainer sheet has no trial copy', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showTunnelsLockedExplainer(context),
                child: const Text('locked'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('locked'));
    await tester.pumpAndSettle();

    expect(find.textContaining('trial'), findsNothing);
    expect(find.textContaining('port forward'), findsOneWidget);
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(find.byType(ProLockedCard), findsOneWidget);
  });

  testWidgets('Add app bar opens tunnel target editor sheet',
      (tester) async {
    final hostId = await seedHost();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          activeTunnelsProvider
              .overrideWith((ref) => Stream.value(const <ActiveTunnel>[])),
        ],
        child: KelolaApp(
          home: TunnelsScreen(
            hostId: hostId,
            clock: () => DateTime.utc(2026, 9, 13, 12),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Add'), findsOneWidget);
    await tester.tap(find.text('Add'));
    // One frame is enough to mount the sheet route; avoid settle/loop.
    await tester.pump();
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(find.text('Add target'), findsWidgets);
    expect(find.byType(KelolaInput), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('editor onSave path upserts preset target through TunnelRepository', () async {
    final hostId = await seedHost();
    final draft = TunnelPresets.apply(
      preset: TunnelPreset.grafana,
      id: 'from-editor',
      hostId: hostId,
      remoteHost: '127.0.0.1',
    );
    final result = validateTunnelTarget(draft);
    expect(result.isOk, isTrue);
    await tunnels.upsert(draft);
    final saved = await tunnels.watchForHost(hostId).first;
    expect(saved, hasLength(1));
    expect(saved.single.label, 'Grafana');
    expect(saved.single.remotePort, 3000);
    expect(saved.single.scheme, TunnelScheme.http);
  });

  testWidgets('saved target from repository appears without target override',
      (tester) async {
    final hostId = await seedHost();
    await tunnels.upsert(
      TunnelTarget(
        id: 'repo-1',
        hostId: hostId,
        label: 'Portainer',
        remoteHost: '127.0.0.1',
        remotePort: 9443,
        scheme: TunnelScheme.https,
        path: '/',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          activeTunnelsProvider
              .overrideWith((ref) => Stream.value(const <ActiveTunnel>[])),
        ],
        child: KelolaApp(
          home: TunnelsScreen(
            hostId: hostId,
            clock: () => DateTime.utc(2026, 9, 13, 12),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Portainer'), findsOneWidget);
    expect(find.textContaining('https://127.0.0.1:9443/'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('active row shows uptime from openedAtUtc', (tester) async {
    final hostId = await seedHost();
    fakeManager.emit([
      _tunnel(
        id: 'a',
        target: _target(hostId: hostId),
        hostAlias: 'web-01',
        state: TunnelState.listening,
      ),
    ]);

    await pumpTunnels(
      tester,
      hostId: hostId,
      clock: () => DateTime.utc(2026, 9, 13, 12, 0, 10),
    );

    expect(find.textContaining('up 10m 10s'), findsOneWidget);
  });

  test('dashboard is the sole production isUnlocked(ProFeature.tunnels) call site', () {
    const needle = 'isUnlocked(ProFeature.tunnels)';
    final dash = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(dash, contains(needle));
    expect(dash, isNot(contains('tunnelsUnlocked')));
    expect(dash, contains('TunnelsScreen'));

    final callSites = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      if (src.contains(needle)) {
        callSites.add(entity.path.replaceAll('\\', '/'));
      }
    }
    expect(callSites, [
      'lib/presentation/screens/host_dashboard_screen.dart',
    ]);
  });

  test('tunnelUptimeLabel formats compact elapsed time', () {
    expect(
      tunnelUptimeLabel(
        DateTime.utc(2026, 9, 13, 11, 50),
        DateTime.utc(2026, 9, 13, 12),
      ),
      '10m 00s',
    );
  });
}
