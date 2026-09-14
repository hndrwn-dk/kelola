import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/keystore/method_channel_hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/ssh/tunnel_bridge.dart';
import 'package:kelola/data/ssh/tunnel_manager.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/data/llm/assist_service.dart';
import 'package:kelola/data/llm/dart_io_llm_http.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/correlation.dart';
import 'package:kelola/domain/llm/preview_gate.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_close_reason.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'package:kelola/domain/entitlement/entitlement.dart'
    show entitlementProvider, entitlementRevisionProvider;

final databaseProvider = Provider<KelolaDatabase>((ref) {
  final db = KelolaDatabase();
  ref.onDispose(db.close);
  return db;
});

final hostRepositoryProvider = Provider<HostRepository>((ref) {
  return HostRepository(ref.watch(databaseProvider));
});

final hardwareSignerProvider = Provider<HardwareSigner>((ref) {
  return MethodChannelHardwareSigner();
});

final enrollmentProvider =
    NotifierProvider<EnrollmentController, EnrollmentState>(
  EnrollmentController.new,
);

class EnrollmentState {
  const EnrollmentState({this.publicBlob, this.authRequired = false, this.backendLabel});

  final Uint8List? publicBlob;
  final bool authRequired;
  final String? backendLabel;

  String? get authorizedKeysLine {
    final blob = publicBlob;
    if (blob == null) {
      return null;
    }
    return OpensshEcdsaP256.authorizedKeysLine(blob);
  }

  String? get oneLiner {
    final blob = publicBlob;
    if (blob == null) {
      return null;
    }
    return OpensshEcdsaP256.enrollmentOneLiner(blob);
  }
}

class EnrollmentController extends Notifier<EnrollmentState> {
  @override
  EnrollmentState build() => const EnrollmentState();

  Future<void> ensureKey() async {
    if (state.publicBlob != null) {
      return;
    }
    const alias = HostRepository.defaultKeyAlias;
    final signer = ref.read(hardwareSignerProvider);
    final repo = ref.read(hostRepositoryProvider);
    final exists = await signer.keyExists(alias);
    final stored = await repo.loadDeviceKey();
    if (exists && stored != null) {
      state = EnrollmentState(
        publicBlob: Uint8List.fromList(base64Decode(stored.blobB64)),
        backendLabel: stored.backend,
      );
      return;
    }
    await _generateAndStore();
  }

  Future<void> regenerateKey() async {
    const alias = HostRepository.defaultKeyAlias;
    final signer = ref.read(hardwareSignerProvider);
    if (await signer.keyExists(alias)) {
      await signer.deleteKey(alias);
    }
    await ref.read(hostRepositoryProvider).clearDeviceKey();
    state = const EnrollmentState();
    await _generateAndStore();
  }

  Future<void> _generateAndStore() async {
    final signer = ref.read(hardwareSignerProvider);
    const alias = HostRepository.defaultKeyAlias;
    final key = await signer.generateKey(alias);
    final q = OpensshEcdsaP256.pointFromSpki(key.publicKeySpki);
    final blob = OpensshEcdsaP256.publicBlobFromPoint(q);
    await ref.read(hostRepositoryProvider).saveDeviceKey(
          blobB64: base64Encode(blob),
          backend: key.backend.name,
        );
    state = EnrollmentState(
      publicBlob: blob,
      authRequired: key.authRequired,
      backendLabel: key.backend.name,
    );
  }
}

final hostKeyPolicyProvider = Provider<HostKeyPolicy>((ref) {
  return HostKeyPolicy(ref.watch(hostRepositoryProvider));
});

final correlationStoreProvider = Provider<CorrelationStore>((ref) {
  return CorrelationStore();
});

final homeWidgetBridgeProvider = Provider<HomeWidgetBridge>((ref) {
  return const MethodChannelHomeWidgetBridge();
});

final llmSettingsProvider = FutureProvider<LlmSettings>((ref) {
  return ref.watch(hostRepositoryProvider).loadLlmSettings();
});

final assistPreviewGateProvider = Provider<AssistPreviewGate>((ref) {
  return AssistPreviewGate();
});

final assistServiceProvider = Provider<AssistService>((ref) {
  return AssistService(
    http: DartIoLlmHttpClient(),
    gate: ref.watch(assistPreviewGateProvider),
  );
});

final sessionPoolProvider = Provider<SshSessionPool>((ref) {
  final pool = SshSessionPool(
    repository: ref.watch(hostRepositoryProvider),
    signer: ref.watch(hardwareSignerProvider),
    hostKeys: ref.watch(hostKeyPolicyProvider),
    correlation: ref.watch(correlationStoreProvider),
    publicBlob: () {
      final blob = ref.read(enrollmentProvider).publicBlob;
      if (blob == null) {
        throw HardwareSignerException('No hardware key generated yet');
      }
      return blob;
    },
  );
  ref.onDispose(pool.closeAll);
  return pool;
});

final tunnelRepositoryProvider = Provider<TunnelRepository>((ref) {
  return TunnelRepository(ref.watch(databaseProvider));
});

final tunnelBridgeProvider = Provider<TunnelBridge>((ref) {
  return MethodChannelTunnelBridge();
});

/// Clamped idle minutes from settings — resolved before [tunnelManagerProvider].
final tunnelIdleMinutesProvider = FutureProvider<int>((ref) {
  return ref.watch(tunnelRepositoryProvider).idleMinutes();
});

final tunnelManagerProvider = Provider<TunnelSessionApi>((ref) {
  final pool = ref.watch(sessionPoolProvider);
  // Awaited via FutureProvider: do not construct against default 10 while pending.
  final idleMinutes = ref.watch(tunnelIdleMinutesProvider).requireValue;

  final manager = TunnelManager(
    pool: pool,
    hosts: ref.watch(hostRepositoryProvider),
    idleMinutes: () => idleMinutes,
  );

  Future<void>? shuttingDown;
  Future<void> shutdown() {
    return shuttingDown ??= () async {
      try {
        await manager.dispose();
      } finally {
        if (identical(pool.closeTunnels, shutdown)) {
          pool.closeTunnels = null;
        }
      }
    }();
  }

  // Keep seam wired through dispose/closeAll so sessionPool.closeAll still
  // awaits tunnel teardown before disconnecting SSH clients.
  pool.closeTunnels = shutdown;

  ref.onDispose(() {
    unawaited(shutdown());
  });
  return manager;
});

/// Keeps FGS notification in sync and routes native Stop all / task-removed.
final tunnelFgsSyncProvider = Provider<TunnelFgsSync>((ref) {
  final bridge = ref.watch(tunnelBridgeProvider);
  final manager = ref.watch(tunnelManagerProvider);
  final sync = TunnelFgsSync(
    bridge: bridge,
    tunnels: manager.watch(),
  );
  sync.attach();
  bridge.setNativeHandler((event) async {
    switch (event) {
      case TunnelNativeEvent.stopAll:
        await manager.closeAll(reason: TunnelCloseReason.user);
      case TunnelNativeEvent.taskRemoved:
        await manager.closeAll(reason: TunnelCloseReason.termination);
    }
  });
  ref.onDispose(() {
    bridge.setNativeHandler(null);
    unawaited(sync.dispose());
  });
  return sync;
});

final activeTunnelsProvider = StreamProvider<List<ActiveTunnel>>((ref) async* {
  // Ensure idle minutes (and thus TunnelManager) are loaded before watching.
  await ref.watch(tunnelIdleMinutesProvider.future);
  // Ensure FGS sync + native handlers stay alive with the active list.
  ref.watch(tunnelFgsSyncProvider);
  yield* ref.watch(tunnelManagerProvider).watch();
});

final tunnelTargetsProvider =
    StreamProvider.family<List<TunnelTarget>, String>((ref, hostId) {
  return ref.watch(tunnelRepositoryProvider).watchForHost(hostId);
});

/// JSON file of free-fleet probe host ids. Widget tests have no path_provider
/// plugin; a per-scope memory store keeps those pumps from crashing. Production
/// always has the plugin.
final fleetProbeSelectionStoreProvider =
    FutureProvider<FleetProbeSelectionStore>((ref) async {
  try {
    final dir = await getApplicationSupportDirectory();
    return FleetProbeSelectionStore(
      File(p.join(dir.path, 'fleet_probe_selection.json')),
    );
  } on MissingPluginException {
    return FleetProbeSelectionStore.memory();
  }
});

class FleetProbeSelectionController extends AsyncNotifier<Set<String>?> {
  @override
  Future<Set<String>?> build() async {
    final hosts = await ref.watch(hostsProvider.future);
    final store = await ref.watch(fleetProbeSelectionStoreProvider.future);
    return store.read(hosts.map((host) => host.id).toSet());
  }

  Future<void> replace(Set<String> ids) async {
    final store = await ref.read(fleetProbeSelectionStoreProvider.future);
    await store.write(ids);
    state = AsyncData(ids);
  }
}

final fleetProbeSelectionProvider =
    AsyncNotifierProvider<FleetProbeSelectionController, Set<String>?>(
  FleetProbeSelectionController.new,
);

/// Live host membership and attention from Drift table watches.
final hostsProvider = StreamProvider<List<Host>>((ref) {
  return ref.watch(hostRepositoryProvider).watchList().map(sortByAttention);
});

final recentsProvider = StreamProvider<List<Host>>((ref) {
  return ref.watch(hostRepositoryProvider).watchRecentHosts();
});

final lastHostIdProvider = StreamProvider<String?>((ref) {
  return ref.watch(hostRepositoryProvider).watchLastHostId();
});

final _searchUnitsFromDbProvider =
    FutureProvider.autoDispose<List<SearchUnit>>((ref) {
  return ref.watch(hostRepositoryProvider).listSearchUnits();
});

final _searchContainersFromDbProvider =
    FutureProvider.autoDispose<List<SearchContainer>>((ref) {
  return ref.watch(hostRepositoryProvider).listSearchContainers();
});

/// Last-known units from the local search index. Filled when UnitsProbe
/// succeeds — search never SSHs to populate it.
final cachedSearchUnitsProvider = Provider.autoDispose<List<SearchUnit>>((ref) {
  return ref.watch(_searchUnitsFromDbProvider).valueOrNull ?? const [];
});

/// Last-known containers from the local search index. Filled when
/// ContainerListProbe succeeds — search never SSHs to populate it.
final cachedSearchContainersProvider =
    Provider.autoDispose<List<SearchContainer>>((ref) {
  return ref.watch(_searchContainersFromDbProvider).valueOrNull ?? const [];
});
