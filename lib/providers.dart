import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/keystore/method_channel_hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/data/llm/assist_service.dart';
import 'package:kelola/data/llm/dart_io_llm_http.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/correlation.dart';
import 'package:kelola/domain/llm/preview_gate.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/domain/search/inventory_search.dart';

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

final hostsProvider = FutureProvider<List<Host>>((ref) async {
  final hosts = await ref.watch(hostRepositoryProvider).list();
  return sortByAttention(hosts);
});

final recentsProvider = FutureProvider<List<Host>>((ref) {
  return ref.watch(hostRepositoryProvider).recentHosts();
});

final lastHostIdProvider = FutureProvider<String?>((ref) {
  return ref.watch(hostRepositoryProvider).lastHostId();
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
