import 'dart:convert';

import 'package:kelola/data/vault/vault_lan.dart';
import 'package:kelola/data/vault/vault_sftp_transport.dart';
import 'package:kelola/data/vault/vault_store.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/data/vault/vault_sftp_probes.dart';
import 'package:kelola/domain/vault/vault.dart';
import 'package:kelola/domain/vault/vault_crypto.dart';
import 'package:kelola/domain/vault/vault_transport.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VaultController {
  VaultController({
    required this.store,
    required this.entitlement,
  });

  final VaultStore store;
  final Entitlement entitlement;

  bool get remoteUnlocked => entitlement.isUnlocked(ProFeature.vaultSync);

  Future<String> exportSealed(String passphrase) async {
    return sealVault(await store.snapshot(), passphrase);
  }

  Future<VaultDiff> previewImport(String blob, String passphrase) async {
    final incoming = await openVault(blob, passphrase);
    return diffVault(
      local: await store.localRecords(),
      incoming: incoming.records,
    );
  }

  Future<void> applyImport(VaultDiff diff) => store.apply(diff);

  Future<void> pushRemote({
    required Host host,
    required String passphrase,
    required WidgetRef ref,
    required BuildContext context,
  }) async {
    if (!entitlement.isUnlocked(ProFeature.vaultSync)) {
      return;
    }
    final sealed = await exportSealed(passphrase);
    if (!context.mounted) {
      return;
    }
    await runHostProbe<void>(
      ref: ref,
      context: context,
      host: host,
      probe: SftpVaultWriteProbe(vaultBlobBytes(sealed)),
    );
  }

  Future<VaultDiff> pullRemote({
    required Host host,
    required String passphrase,
    required WidgetRef ref,
    required BuildContext context,
  }) async {
    if (!entitlement.isUnlocked(ProFeature.vaultSync)) {
      return const VaultDiff(added: [], updated: [], deleted: []);
    }
    final bytes = await runHostProbe<List<int>>(
      ref: ref,
      context: context,
      host: host,
      probe: const SftpVaultReadProbe(),
    );
    return previewImport(vaultBlobString(bytes), passphrase);
  }

  Future<String> startLanOffer() async {
    if (!vaultTransportRequiresUnlock(VaultTransportKind.lan) ||
        !entitlement.isUnlocked(ProFeature.vaultSync)) {
      return '';
    }
    final session = await VaultLanSession.offer();
    _lan = session;
    return session.token;
  }

  Future<void> sendLan(String token, String passphrase) async {
    if (!entitlement.isUnlocked(ProFeature.vaultSync)) {
      return;
    }
    await VaultLanSession.send(
      token,
      vaultBlobBytes(await exportSealed(passphrase)),
    );
  }

  Future<VaultDiff> receiveLan(String passphrase) async {
    final session = _lan;
    if (session == null) {
      throw StateError('No LAN vault offer');
    }
    final blob = utf8.decode(await session.wait());
    await session.close();
    _lan = null;
    return previewImport(blob, passphrase);
  }

  VaultLanSession? _lan;
}
