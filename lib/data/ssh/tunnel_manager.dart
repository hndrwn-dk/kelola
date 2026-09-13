import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_close_reason.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:uuid/uuid.dart';

/// Max simultaneous forwarded channels per active tunnel.
const int kTunnelMaxChannels = 8;

/// Debounce for channel-count / dropped-count stream emissions.
const Duration kTunnelChannelEmitDebounce = Duration(milliseconds: 500);

/// Binds an ephemeral server socket on IPv4 loopback only.
Future<ServerSocket> bindLoopbackEphemeral() {
  return ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
}

typedef TunnelBindFn = Future<ServerSocket> Function();

typedef TunnelOpenChannelFn = Future<SSHSocket> Function({
  required SSHClient client,
  required String remoteHost,
  required int remotePort,
});

/// Production poll interval for idle deadline checks against the injected clock.
///
/// Tests inject a shorter [TunnelManager.idlePollInterval] so FakeAsync /
/// wall-clock pumps stay fast.
const Duration kTunnelIdlePollInterval = Duration(seconds: 1);

/// UI / provider surface for [TunnelManager] (and fakes in tests).
abstract class TunnelSessionApi {
  Stream<List<ActiveTunnel>> watch();

  Future<ActiveTunnel> open(
    TunnelTarget target, {
    required String hostAlias,
  });

  Future<void> close(
    String tunnelId, {
    TunnelCloseReason reason = TunnelCloseReason.user,
  });

  Future<void> closeAll({
    TunnelCloseReason reason = TunnelCloseReason.termination,
  });

  void dismissFailed(String tunnelId);

  Future<ActiveTunnel> retry(String tunnelId);
}

/// Owns loopback listeners and SSH local forwards for active tunnels.
///
/// One open + one close (or one failure) audit per tunnel lifecycle — never
/// per forwarded channel.
class TunnelManager implements TunnelSessionApi {
  TunnelManager({
    required SshSessionPool pool,
    required HostRepository hosts,
    DateTime Function()? clock,
    int Function()? idleMinutes,
    TunnelBindFn? bind,
    TunnelOpenChannelFn? openChannel,
    String Function()? newId,
    Duration idlePollInterval = kTunnelIdlePollInterval,
  })  : _pool = pool,
        _hosts = hosts,
        _clock = clock ?? DateTime.now,
        _idleMinutes = idleMinutes ?? (() => 10),
        _bind = bind ?? bindLoopbackEphemeral,
        _openChannel = openChannel ?? _defaultOpenChannel,
        _newId = newId ?? (() => const Uuid().v7()),
        _idlePollInterval = idlePollInterval;

  final SshSessionPool _pool;
  final HostRepository _hosts;
  final DateTime Function() _clock;
  final int Function() _idleMinutes;
  final TunnelBindFn _bind;
  final TunnelOpenChannelFn _openChannel;
  final String Function() _newId;
  final Duration _idlePollInterval;

  final _sessions = <String, _TunnelSession>{};
  final _lastCloseReasons = <String, TunnelCloseReason>{};
  final _controller = StreamController<List<ActiveTunnel>>.broadcast();
  final _clientDropArmed = <String>{};
  Timer? _channelDebounce;
  Timer? _idlePoll;

  /// Idle timeout minutes from the injected callback (clamped by callers).
  int get idleMinutes => _idleMinutes();

  /// Synchronous snapshot (channel counts update immediately).
  List<ActiveTunnel> get current =>
      _sessions.values.map((s) => s.snapshot()).toList(growable: false);

  /// Bound server sockets still accepting (debug / tests).
  int get debugListenerCount =>
      _sessions.values.where((s) => s.server != null).length;

  /// Established channels across all sessions (debug / tests).
  int get debugLiveChannelCount =>
      _sessions.values.fold<int>(0, (n, s) => n + s.channels.length);

  /// In-flight openChannel reservations (debug / tests).
  int get debugOpeningCount =>
      _sessions.values.fold<int>(0, (n, s) => n + s.opening);

  /// Local sockets waiting on openChannel (debug / tests).
  int get debugInFlightLocalCount =>
      _sessions.values.fold<int>(0, (n, s) => n + s.inFlightLocals.length);

  /// Session closeReason for tests (null if unknown / absent).
  TunnelCloseReason? debugCloseReason(String tunnelId) =>
      _sessions[tunnelId]?.closeReason ?? _lastCloseReasons[tunnelId];

  @override
  Stream<List<ActiveTunnel>> watch() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<ActiveTunnel> open(
    TunnelTarget target, {
    required String hostAlias,
  }) async {
    final id = _newId();
    final session = _TunnelSession(
      id: id,
      target: target,
      hostAlias: hostAlias,
      openedAtUtc: _clock().toUtc(),
    );
    _sessions[id] = session;
    _emit();

    try {
      final server = await _bind();
      session.server = server;
      session.localPort = server.port;
      session.state = TunnelState.listening;
      _emit();

      final host = await _hosts.get(target.hostId);
      if (host == null) {
        throw StateError('Host ${target.hostId} not found');
      }
      final client = await _pool.acquireTunnelClient(host);
      session.client = client;
      session.hostId = host.id;
      session.remoteUser = host.username;
      _armClientDrop(client, host.id);

      _startAcceptLoop(session);
      _armIdle(session);
      await _recordOpenAudit(session);
      return session.snapshot();
    } catch (e) {
      await _closeServer(session);
      session.state = TunnelState.failed;
      session.closeReason = TunnelCloseReason.failed;
      session.errorSummary = describeSshError(e);
      _lastCloseReasons[id] = TunnelCloseReason.failed;
      try {
        await _recordFailureAudit(session);
      } catch (_) {}
      await _maybeReleaseTunnelClient(session);
      _emit();
      return session.snapshot();
    }
  }

  @override
  Future<void> close(
    String tunnelId, {
    TunnelCloseReason reason = TunnelCloseReason.user,
  }) async {
    final session = _sessions[tunnelId];
    if (session == null) return;
    if (session.state == TunnelState.closed ||
        session.state == TunnelState.closing) {
      return;
    }
    session.closeReason = reason;
    session.state = TunnelState.closing;
    session.closesAtUtc = null;
    _lastCloseReasons[tunnelId] = reason;
    _emit();
    try {
      await _shutdownSession(session);
    } finally {
      _sessions.remove(tunnelId);
      await _maybeReleaseTunnelClient(session);
      _maybeStopIdlePoll();
      try {
        await _recordCloseAudit(session, reason);
      } catch (_) {}
      _emit();
    }
  }

  @override
  Future<void> closeAll({
    TunnelCloseReason reason = TunnelCloseReason.termination,
  }) async {
    final ids = _sessions.keys.toList(growable: false);
    for (final id in ids) {
      await close(id, reason: reason);
    }
  }

  @override
  void dismissFailed(String tunnelId) {
    final session = _sessions[tunnelId];
    if (session == null || session.state != TunnelState.failed) return;
    _sessions.remove(tunnelId);
    _emit();
  }

  @override
  Future<ActiveTunnel> retry(String tunnelId) async {
    final session = _sessions[tunnelId];
    if (session == null || session.state != TunnelState.failed) {
      throw StateError('Tunnel $tunnelId is not failed');
    }
    final target = session.target;
    final hostAlias = session.hostAlias;
    _sessions.remove(tunnelId);
    _emit();
    return open(target, hostAlias: hostAlias);
  }

  Future<void> dispose() async {
    _channelDebounce?.cancel();
    _idlePoll?.cancel();
    _idlePoll = null;
    await closeAll();
    await _controller.close();
  }

  Duration _idleDuration() {
    final minutes = _idleMinutes().clamp(2, 60);
    return Duration(minutes: minutes);
  }

  void _armIdle(_TunnelSession session) {
    if (session.state != TunnelState.listening &&
        session.state != TunnelState.idleClosing) {
      return;
    }
    if (session.channels.isNotEmpty || session.opening > 0) return;
    session.closesAtUtc = _clock().toUtc().add(_idleDuration());
    if (session.state == TunnelState.idleClosing) {
      session.state = TunnelState.listening;
    }
    _ensureIdlePoll();
    _emit();
  }

  void _clearIdleOnActivity(_TunnelSession session) {
    final wasClosing = session.state == TunnelState.idleClosing;
    final hadDeadline = session.closesAtUtc != null;
    session.closesAtUtc = null;
    if (wasClosing) {
      session.state = TunnelState.listening;
    }
    if (wasClosing || hadDeadline) {
      _maybeStopIdlePoll();
      _emit();
    }
  }

  void _ensureIdlePoll() {
    _idlePoll ??= Timer.periodic(_idlePollInterval, (_) => _tickIdle());
  }

  void _maybeStopIdlePoll() {
    final anyArmed = _sessions.values.any((s) => s.closesAtUtc != null);
    if (!anyArmed) {
      _idlePoll?.cancel();
      _idlePoll = null;
    }
  }

  void _tickIdle() {
    final now = _clock().toUtc();
    for (final session in _sessions.values.toList(growable: false)) {
      final closesAt = session.closesAtUtc;
      if (closesAt == null) continue;
      if (session.state != TunnelState.listening &&
          session.state != TunnelState.idleClosing) {
        continue;
      }
      if (session.channels.isNotEmpty || session.opening > 0) continue;

      if (!now.isBefore(closesAt)) {
        unawaited(close(session.id, reason: TunnelCloseReason.idle));
        continue;
      }

      final warnAt = closesAt.subtract(const Duration(minutes: 1));
      if (session.state == TunnelState.listening && !now.isBefore(warnAt)) {
        session.state = TunnelState.idleClosing;
        _emit();
      }
    }
    _maybeStopIdlePoll();
  }

  void _startAcceptLoop(_TunnelSession session) {
    final server = session.server;
    if (server == null) return;
    session.acceptSub = server.listen(
      (socket) => unawaited(_onAccept(session, socket)),
      onError: (Object e) {
        if (session.state == TunnelState.listening ||
            session.state == TunnelState.idleClosing) {
          unawaited(_failSession(session, describeSshError(e)));
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _rejectOverCap(_TunnelSession session, Socket socket) async {
    session.droppedChannels++;
    try {
      await socket.close();
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
    _emit(channelOnly: true);
  }

  Future<void> _onAccept(_TunnelSession session, Socket socket) async {
    if (session.state != TunnelState.listening &&
        session.state != TunnelState.idleClosing) {
      socket.destroy();
      return;
    }
    if (session.liveChannelCount >= kTunnelMaxChannels) {
      await _rejectOverCap(session, socket);
      return;
    }

    _clearIdleOnActivity(session);
    session.opening++;
    session.inFlightLocals.add(socket);
    SSHSocket? remote;
    try {
      final client = session.client;
      if (client == null || client.isClosed) {
        _releaseInFlight(session, socket);
        socket.destroy();
        await _failSession(session, 'SSH tunnel client is closed');
        return;
      }
      remote = await _openChannel(
        client: client,
        remoteHost: session.target.remoteHost,
        remotePort: session.target.remotePort,
      );
    } catch (e) {
      _releaseInFlight(session, socket);
      socket.destroy();
      await _failSession(session, describeSshError(e));
      return;
    }

    // close / closeAll / _failSession may have run during openChannel.
    if (!_sessions.containsKey(session.id) ||
        (session.state != TunnelState.listening &&
            session.state != TunnelState.idleClosing)) {
      _releaseInFlight(session, socket);
      try {
        socket.destroy();
      } catch (_) {}
      try {
        remote.destroy();
      } catch (_) {}
      if (_sessions.containsKey(session.id) &&
          (session.state == TunnelState.listening ||
              session.state == TunnelState.idleClosing) &&
          session.channels.isEmpty &&
          session.opening == 0) {
        _armIdle(session);
      }
      return;
    }

    // Add channel before releasing the opening slot so idle is not re-armed mid-handoff.
    final channel = _LiveChannel(local: socket, remote: remote);
    session.channels.add(channel);
    _releaseInFlight(session, socket);
    _clearIdleOnActivity(session);
    _emit(channelOnly: true);

    try {
      await _pipe(socket, remote);
    } finally {
      session.channels.remove(channel);
      try {
        socket.destroy();
      } catch (_) {}
      try {
        remote.destroy();
      } catch (_) {}
      if (_sessions.containsKey(session.id) &&
          (session.state == TunnelState.listening ||
              session.state == TunnelState.idleClosing)) {
        if (session.channels.isEmpty && session.opening == 0) {
          _armIdle(session);
        } else {
          _emit(channelOnly: true);
        }
      }
    }
  }

  void _releaseInFlight(_TunnelSession session, Socket socket) {
    if (session.inFlightLocals.remove(socket)) {
      if (session.opening > 0) session.opening--;
    }
  }

  Future<void> _pipe(Socket local, SSHSocket remote) async {
    final done = Completer<void>();
    late final StreamSubscription<List<int>> localSub;
    late final StreamSubscription<Uint8List> remoteSub;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    localSub = local.listen(
      (data) {
        try {
          remote.sink.add(data);
        } catch (_) {
          finish();
        }
      },
      onError: (_) => finish(),
      onDone: finish,
      cancelOnError: true,
    );

    remoteSub = remote.stream.listen(
      (data) {
        try {
          local.add(data);
        } catch (_) {
          finish();
        }
      },
      onError: (_) => finish(),
      onDone: finish,
      cancelOnError: true,
    );

    await done.future;
    await localSub.cancel();
    await remoteSub.cancel();
  }

  void _armClientDrop(SSHClient client, String hostId) {
    if (!_clientDropArmed.add(hostId)) return;
    client.done.then(
      (_) => _onClientDropped(hostId),
      onError: (_) => _onClientDropped(hostId),
    );
  }

  void _onClientDropped(String hostId) {
    _clientDropArmed.remove(hostId);
    final victims = _sessions.values
        .where(
          (s) =>
              s.hostId == hostId &&
              (s.state == TunnelState.listening ||
                  s.state == TunnelState.idleClosing ||
                  s.state == TunnelState.starting),
        )
        .toList(growable: false);
    for (final session in victims) {
      unawaited(_failSession(session, 'SSH tunnel client disconnected'));
    }
  }

  Future<void> _failSession(_TunnelSession session, String summary) async {
    if (session.state == TunnelState.failed ||
        session.state == TunnelState.closing ||
        session.state == TunnelState.closed) {
      return;
    }
    session.closeReason = TunnelCloseReason.failed;
    session.state = TunnelState.failed;
    session.errorSummary = summary;
    session.closesAtUtc = null;
    _lastCloseReasons[session.id] = TunnelCloseReason.failed;
    _emit();
    try {
      await _shutdownSession(session);
    } finally {
      await _maybeReleaseTunnelClient(session);
      _maybeStopIdlePoll();
      try {
        await _recordCloseAudit(
          session,
          TunnelCloseReason.failed,
          errorSummary: summary,
        );
      } catch (_) {}
      _emit();
    }
  }

  Future<void> _recordOpenAudit(_TunnelSession session) async {
    if (session.auditOpenWritten || session.auditCloseWritten) return;
    session.auditOpenWritten = true;
    try {
      await _hosts.recordAudit(
        hostId: session.target.hostId,
        hostAlias: session.hostAlias,
        remoteUser: await _remoteUserFor(session),
        title: _openTitle(session),
        command: _forwardCommand(session),
        risk: RiskLevel.read.name,
        usedSudo: false,
        closeReason: TunnelCloseReason.open.value,
      );
    } catch (_) {
      // Open must still succeed if audit persistence fails.
    }
  }

  Future<void> _recordCloseAudit(
    _TunnelSession session,
    TunnelCloseReason reason, {
    String? errorSummary,
  }) async {
    if (session.auditCloseWritten) return;
    session.auditCloseWritten = true;
    final lifetime =
        _clock().toUtc().difference(session.openedAtUtc).inMilliseconds;
    await _hosts.recordAudit(
      hostId: session.target.hostId,
      hostAlias: session.hostAlias,
      remoteUser: await _remoteUserFor(session),
      title: _closeTitle(session, reason),
      command: _forwardCommand(session),
      risk: RiskLevel.read.name,
      usedSudo: false,
      durationMs: lifetime < 0 ? 0 : lifetime,
      errorSummary: errorSummary ?? session.errorSummary,
      closeReason: reason.value,
    );
  }

  Future<void> _recordFailureAudit(_TunnelSession session) async {
    if (session.auditCloseWritten) return;
    session.auditCloseWritten = true;
    await _hosts.recordAudit(
      hostId: session.target.hostId,
      hostAlias: session.hostAlias,
      remoteUser: await _remoteUserFor(session),
      title: _openTitle(session),
      command: _forwardCommand(session),
      risk: RiskLevel.read.name,
      usedSudo: false,
      errorSummary: session.errorSummary,
      closeReason: TunnelCloseReason.failed.value,
    );
  }

  Future<String> _remoteUserFor(_TunnelSession session) async {
    final cached = session.remoteUser;
    if (cached != null) return cached;
    final host = await _hosts.get(session.target.hostId);
    final user = host?.username ?? '';
    session.remoteUser = user;
    return user;
  }

  static String _openTitle(_TunnelSession session) {
    final t = session.target;
    return 'Open tunnel → ${t.label} (${t.remotePort})';
  }

  static String _closeTitle(_TunnelSession session, TunnelCloseReason reason) {
    final t = session.target;
    return 'Close tunnel → ${t.label} (${t.remotePort}) [${reason.value}]';
  }

  static String _forwardCommand(_TunnelSession session) {
    final t = session.target;
    return 'ssh -L 127.0.0.1:${session.localPort}:${t.remoteHost}:${t.remotePort}';
  }

  Future<void> _shutdownSession(_TunnelSession session) async {
    await session.acceptSub?.cancel();
    session.acceptSub = null;
    for (final local in List<Socket>.from(session.inFlightLocals)) {
      try {
        local.destroy();
      } catch (_) {}
    }
    session.inFlightLocals.clear();
    session.opening = 0;
    for (final ch in List<_LiveChannel>.from(session.channels)) {
      try {
        ch.local.destroy();
      } catch (_) {}
      try {
        ch.remote.destroy();
      } catch (_) {}
    }
    session.channels.clear();
    await _closeServer(session);
    session.client = null;
  }

  /// True while any non-failed session for [hostId] still needs the SSH client.
  bool _hostNeedsTunnelClient(String hostId, {String? exceptId}) {
    return _sessions.values.any((s) {
      if (exceptId != null && s.id == exceptId) return false;
      if (s.hostId != hostId && s.target.hostId != hostId) return false;
      switch (s.state) {
        case TunnelState.starting:
        case TunnelState.listening:
        case TunnelState.idleClosing:
        case TunnelState.closing:
          return true;
        case TunnelState.failed:
        case TunnelState.closed:
          return false;
      }
    });
  }

  Future<void> _maybeReleaseTunnelClient(_TunnelSession session) async {
    final hostId = session.hostId ?? session.target.hostId;
    if (_hostNeedsTunnelClient(hostId, exceptId: session.id)) return;
    session.client = null;
    await _pool.releaseTunnelClient(hostId);
  }

  Future<void> _closeServer(_TunnelSession session) async {
    final server = session.server;
    session.server = null;
    if (server == null) return;
    try {
      await server.close();
    } catch (_) {}
  }

  void _emit({bool channelOnly = false}) {
    if (channelOnly) {
      _channelDebounce?.cancel();
      _channelDebounce = Timer(kTunnelChannelEmitDebounce, () {
        if (!_controller.isClosed) {
          _controller.add(current);
        }
      });
      return;
    }
    _channelDebounce?.cancel();
    _channelDebounce = null;
    if (!_controller.isClosed) {
      _controller.add(current);
    }
  }

  static Future<SSHSocket> _defaultOpenChannel({
    required SSHClient client,
    required String remoteHost,
    required int remotePort,
  }) {
    return client.forwardLocal(remoteHost, remotePort);
  }
}

class _LiveChannel {
  _LiveChannel({required this.local, required this.remote});

  final Socket local;
  final SSHSocket remote;
}

class _TunnelSession {
  _TunnelSession({
    required this.id,
    required this.target,
    required this.hostAlias,
    required this.openedAtUtc,
  });

  final String id;
  final TunnelTarget target;
  final String hostAlias;
  final DateTime openedAtUtc;

  String? hostId;
  String? remoteUser;
  SSHClient? client;
  ServerSocket? server;
  StreamSubscription<Socket>? acceptSub;
  final channels = <_LiveChannel>[];
  /// Locals accepted but not yet added to [channels] (openChannel in flight).
  final inFlightLocals = <Socket>{};

  TunnelState state = TunnelState.starting;
  int localPort = 0;
  int droppedChannels = 0;
  /// Reserved slots while `openChannel` is in flight (cap fairness).
  int opening = 0;
  DateTime? closesAtUtc;
  String? errorSummary;
  TunnelCloseReason? closeReason;
  bool auditOpenWritten = false;
  bool auditCloseWritten = false;

  int get liveChannelCount => channels.length + opening;

  ActiveTunnel snapshot() {
    return ActiveTunnel(
      id: id,
      target: target,
      hostAlias: hostAlias,
      localPort: localPort,
      state: state,
      openedAtUtc: openedAtUtc,
      openChannels: channels.length,
      closesAtUtc: closesAtUtc,
      errorSummary: errorSummary,
      droppedChannels: droppedChannels,
    );
  }
}
