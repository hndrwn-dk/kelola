import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/ssh/tunnel_bridge.dart';
import 'package:kelola/data/ssh/tunnel_manager.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_close_reason.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/providers.dart';

void main() {
  test('SshSessionPool.closeAll awaits closeTunnels callback', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final order = <String>[];
    final pool = SshSessionPool(
      repository: repo,
      signer: _NoopSigner(),
      hostKeys: HostKeyPolicy(repo),
      publicBlob: () => Uint8List(0),
    );
    pool.closeTunnels = () async {
      order.add('tunnels');
    };

    await pool.closeAll();

    expect(order, ['tunnels']);
  });

  test('tunnelFgsSyncProvider maps stopAll→user and taskRemoved→termination',
      () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final bridge = _CapturingBridge();
    final closeReasons = <TunnelCloseReason>[];
    final manager = _RecordingSessionApi(closeReasons);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tunnelBridgeProvider.overrideWithValue(bridge),
        tunnelManagerProvider.overrideWithValue(manager),
      ],
    );
    addTearDown(container.dispose);

    container.read(tunnelFgsSyncProvider);
    expect(bridge.handler, isNotNull);

    await bridge.handler!(TunnelNativeEvent.stopAll);
    await bridge.handler!(TunnelNativeEvent.taskRemoved);

    expect(closeReasons, [
      TunnelCloseReason.user,
      TunnelCloseReason.termination,
    ]);
  });

  test('tunnelManagerProvider wires idle minutes from repository', () async {
    final providersSrc = File('lib/providers.dart').readAsStringSync();
    expect(providersSrc, contains('.idleMinutes()'));
    expect(
      providersSrc,
      isNot(contains('idleMinutes: () => TunnelRepository.defaultIdleMinutes')),
    );
    expect(providersSrc, isNot(contains('unawaited(tunnels.idleMinutes()')));

    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final tunnels = TunnelRepository(db);
    await tunnels.setIdleMinutes(45);

    final bridge = _CapturingBridge();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tunnelRepositoryProvider.overrideWithValue(tunnels),
        tunnelBridgeProvider.overrideWithValue(bridge),
        hardwareSignerProvider.overrideWithValue(_NoopSigner()),
        enrollmentProvider.overrideWith(_FixedEnrollment.new),
      ],
    );
    addTearDown(container.dispose);

    // Manager is only constructed after idle minutes resolve (not default 10).
    await container.read(tunnelIdleMinutesProvider.future);
    container.read(tunnelFgsSyncProvider);
    final api = container.read(tunnelManagerProvider);
    expect(api, isA<TunnelManager>());
    expect((api as TunnelManager).idleMinutes, 45);
  });

  test('tunnelFgsSyncProvider clears native handler on dispose', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final bridge = _CapturingBridge();
    final manager = _RecordingSessionApi([]);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tunnelBridgeProvider.overrideWithValue(bridge),
        tunnelManagerProvider.overrideWithValue(manager),
      ],
    );

    container.read(tunnelFgsSyncProvider);
    expect(bridge.handler, isNotNull);

    container.dispose();
    expect(bridge.handler, isNull);
  });

  test('docs/specs and docs/play FGS declaration exist', () {
    expect(File('docs/specs/m5-tunnels.md').existsSync(), isTrue);
    expect(File('docs/play/fgs-declaration.md').existsSync(), isTrue);
    final spec = File('docs/specs/m5-tunnels.md').readAsStringSync();
    expect(spec, contains('loopback'));
    expect(spec, contains('specialUse'));
    final play = File('docs/play/fgs-declaration.md').readAsStringSync();
    expect(play, contains('Stop all'));
    expect(play, contains('specialUse'));
  });
}

class _CapturingBridge implements TunnelBridge {
  TunnelNativeHandler? handler;

  @override
  Future<void> start({required String text}) async {}

  @override
  Future<void> update({required String text}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<bool> requestPostNotifications() async => true;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  void setNativeHandler(TunnelNativeHandler? h) {
    handler = h;
  }
}

class _RecordingSessionApi implements TunnelSessionApi {
  _RecordingSessionApi(this.closeReasons);

  final List<TunnelCloseReason> closeReasons;
  final _controller = StreamController<List<ActiveTunnel>>.broadcast();

  @override
  Stream<List<ActiveTunnel>> watch() async* {
    yield const [];
    yield* _controller.stream;
  }

  @override
  Future<ActiveTunnel> open(
    TunnelTarget target, {
    required String hostAlias,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> close(
    String tunnelId, {
    TunnelCloseReason reason = TunnelCloseReason.user,
  }) async {}

  @override
  void dismissFailed(String tunnelId) {}

  @override
  Future<ActiveTunnel> retry(String tunnelId) {
    throw UnimplementedError();
  }

  @override
  Future<void> closeAll({
    TunnelCloseReason reason = TunnelCloseReason.termination,
  }) async {
    closeReasons.add(reason);
  }
}

class _NoopSigner implements HardwareSigner {
  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<HardwareKey> generateKey(String alias) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteKey(String alias) async {}

  @override
  Future<Uint8List> sign(String alias, Uint8List data) {
    throw UnimplementedError();
  }

  @override
  Future<void> confirmPresence({String reason = 'Confirm destructive action'}) {
    throw UnimplementedError();
  }
}

class _FixedEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() => EnrollmentState(
        publicBlob: Uint8List.fromList(List<int>.filled(65, 1)),
      );
}
