import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/tunnel_bridge.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

void main() {
  test('Kotlin FGS uses FOREGROUND_SERVICE_TYPE_SPECIAL_USE / specialUse', () {
    final service = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/TunnelForegroundService.kt',
    ).readAsStringSync();
    expect(service, contains('FOREGROUND_SERVICE_TYPE_SPECIAL_USE'));
    expect(service.toLowerCase(), contains('specialuse'));
    expect(service, contains('Stop all'));
    expect(service, contains('setOngoing(true)'));
    expect(service, contains('onTaskRemoved'));
    expect(service, contains('START_NOT_STICKY'));
    expect(RegExp(r'\bSTART_STICKY\b').hasMatch(service), isFalse);
    expect(service, contains('NotificationManager'));
    expect(service, contains('manager.notify'));
    expect(service, contains('ic_tunnel_notification'));
    expect(
      service,
      contains('Process death must not resurrect a tunnel-less FGS'),
    );
    expect(service, contains('START_NOT_STICKY'));
    expect(service.contains('return START_STICKY'), isFalse);
    expect(service, contains('NotificationManager'));
    expect(service, contains('manager.notify'));
    expect(service, contains('ic_tunnel_notification'));
    // update() must not re-enter startForegroundService (Android 12+ crash).
    final updateStart = service.indexOf('fun update(context: Context, text: String)');
    expect(updateStart, greaterThanOrEqualTo(0));
    final updateEnd = service.indexOf('\n        fun stop(', updateStart);
    final updateBody = service.substring(updateStart, updateEnd);
    expect(updateBody, contains('notify'));
    expect(updateBody, isNot(contains('startForegroundService')));

    final drawable = File(
      'android/app/src/main/res/drawable/ic_tunnel_notification.xml',
    );
    expect(drawable.existsSync(), isTrue);

    final plugin = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/TunnelPlugin.kt',
    ).readAsStringSync();
    expect(plugin, contains('kelola/tunnels'));
    expect(plugin, contains('requestPostNotifications'));
    expect(plugin, contains('stopAll'));

    final main = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/MainActivity.kt',
    ).readAsStringSync();
    expect(main, contains('TunnelPlugin()'));

    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('foregroundServiceType="specialUse"'));
  });

  test('notification text format and idleClosing countdown', () {
    final listening = ActiveTunnel(
      id: 'a',
      target: const TunnelTarget(
        id: 't1',
        hostId: 'h1',
        label: 'Cockpit',
        remoteHost: '127.0.0.1',
        remotePort: 9090,
        scheme: TunnelScheme.https,
        path: '/',
      ),
      hostAlias: 'web-01',
      localPort: 4242,
      state: TunnelState.listening,
      openedAtUtc: DateTime.utc(2026, 9, 13),
      openChannels: 0,
    );
    final closing = ActiveTunnel(
      id: 'b',
      target: const TunnelTarget(
        id: 't2',
        hostId: 'h2',
        label: 'Grafana',
        remoteHost: '127.0.0.1',
        remotePort: 3000,
        scheme: TunnelScheme.http,
        path: '/',
      ),
      hostAlias: 'db-02',
      localPort: 4243,
      state: TunnelState.idleClosing,
      openedAtUtc: DateTime.utc(2026, 9, 13),
      openChannels: 0,
      closesAtUtc: DateTime.utc(2026, 9, 13, 12, 1, 0),
    );

    expect(
      formatTunnelNotificationText(
        [listening, closing],
        now: DateTime.utc(2026, 9, 13, 12, 0, 30),
      ),
      '2 tunnels active · web-01, db-02 · closes in 30s',
    );
    expect(
      formatTunnelNotificationText(
        [closing],
        now: DateTime.utc(2026, 9, 13, 12, 0, 30),
      ),
      '1 tunnel active · db-02 · closes in 30s',
    );
  });

  test('sync stops FGS within 1s after manager emits empty live list', () {
    fakeAsync((async) {
      final bridge = _RecordingBridge();
      final controller = StreamController<List<ActiveTunnel>>.broadcast();
      final sync = TunnelFgsSync(
        bridge: bridge,
        tunnels: controller.stream,
      );
      sync.attach();
      async.flushMicrotasks();

      final live = ActiveTunnel(
        id: 'a',
        target: const TunnelTarget(
          id: 't1',
          hostId: 'h1',
          label: 'Cockpit',
          remoteHost: '127.0.0.1',
          remotePort: 9090,
          scheme: TunnelScheme.https,
          path: '/',
        ),
        hostAlias: 'web-01',
        localPort: 4242,
        state: TunnelState.listening,
        openedAtUtc: DateTime.utc(2026, 9, 13),
        openChannels: 0,
      );

      controller.add([live]);
      async.flushMicrotasks();
      expect(bridge.calls, ['start']);

      final updated = ActiveTunnel(
        id: live.id,
        target: live.target,
        hostAlias: 'db-02',
        localPort: live.localPort,
        state: TunnelState.listening,
        openedAtUtc: live.openedAtUtc,
        openChannels: 0,
      );
      controller.add([updated]);
      async.flushMicrotasks();
      expect(bridge.calls, ['start', 'update']);

      controller.add(const []);
      async.flushMicrotasks();
      expect(bridge.calls.last, 'stop');

      // Stop is recorded immediately (within the 1s budget).
      async.elapse(const Duration(milliseconds: 999));
      expect(bridge.calls.where((c) => c == 'stop').length, 1);

      sync.dispose();
      controller.close();
    });
  });

  test('idleClosing triggers periodic notification countdown updates', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 9, 13, 12, 0, 0);
      final bridge = _RecordingBridge();
      final controller = StreamController<List<ActiveTunnel>>.broadcast();
      final sync = TunnelFgsSync(
        bridge: bridge,
        tunnels: controller.stream,
        clock: () => now,
        countdownTick: const Duration(seconds: 1),
      );
      sync.attach();
      async.flushMicrotasks();

      final closing = ActiveTunnel(
        id: 'a',
        target: const TunnelTarget(
          id: 't1',
          hostId: 'h1',
          label: 'Cockpit',
          remoteHost: '127.0.0.1',
          remotePort: 9090,
          scheme: TunnelScheme.https,
          path: '/',
        ),
        hostAlias: 'web-01',
        localPort: 4242,
        state: TunnelState.idleClosing,
        openedAtUtc: DateTime.utc(2026, 9, 13, 11, 50),
        openChannels: 0,
        closesAtUtc: DateTime.utc(2026, 9, 13, 12, 1, 0),
      );

      controller.add([closing]);
      async.flushMicrotasks();
      expect(bridge.texts, ['1 tunnel active · web-01 · closes in 60s']);

      now = now.add(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(bridge.texts.last, '1 tunnel active · web-01 · closes in 59s');
      expect(bridge.calls.where((c) => c == 'update').length, 1);

      sync.dispose();
      controller.close();
    });
  });
}

class _RecordingBridge implements TunnelBridge {
  final calls = <String>[];
  final texts = <String>[];

  @override
  Future<void> start({required String text}) async {
    calls.add('start');
    texts.add(text);
  }

  @override
  Future<void> update({required String text}) async {
    calls.add('update');
    texts.add(text);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<bool> requestPostNotifications() async => true;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  void setNativeHandler(TunnelNativeHandler? handler) {}
}
