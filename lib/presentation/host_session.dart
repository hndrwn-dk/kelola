import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/ssh_host_key_flow.dart';
import 'package:kelola/providers.dart';

Future<T> runHostProbe<T>({
  required WidgetRef ref,
  required BuildContext context,
  required Host host,
  required Probe<T> probe,
  HostFacts? facts,
}) {
  return ref.read(sessionPoolProvider).execute(
        host,
        probe,
        facts: facts,
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
