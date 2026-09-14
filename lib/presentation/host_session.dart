import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/presentation/ssh_host_key_flow.dart';
import 'package:kelola/providers.dart';

String watchedHostAlias(WidgetRef ref, String hostId) {
  final hosts = ref.watch(hostsProvider).asData?.value;
  if (hosts == null) {
    return '';
  }
  for (final host in hosts) {
    if (host.id == hostId) {
      return host.alias;
    }
  }
  return '';
}

Future<T> runHostProbe<T>({
  required WidgetRef ref,
  required BuildContext context,
  required Host host,
  required Probe<T> probe,
  HostFacts? facts,
  void Function(int done, int? total)? onProgress,
  TransferCancel? cancel,
  ProbeScope scope = ProbeScope.host,
}) {
  return ref.read(sessionPoolProvider).execute(
        host,
        probe,
        facts: facts,
        onProgress: onProgress,
        cancel: cancel,
        scope: scope,
        onUnknownHostKey: (hostId, algorithm, fingerprint) {
          return promptUnknownHostKey(
            context,
            hostId: hostId,
            algorithm: algorithm,
            fingerprint: fingerprint,
          );
        },
      );
}
