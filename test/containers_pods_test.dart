import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/domain/containers/container_list_view.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/container_inspect_probe.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/screens/containers_screen.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/providers.dart';

import 'support/fakes.dart';

const _pod = ContainerRow(
  id: 'default/nginx-7b8b87776c-6qfpt',
  names: 'nginx-7b8b87776c-6qfpt',
  namespace: 'default',
  image: 'nginx:alpine',
  state: 'running',
  status: 'Running',
  engine: 'k8s',
);

const _docker = ContainerRow(
  id: 'abc',
  names: 'watchtower',
  image: 'containrrr/watchtower',
  state: 'running',
  status: 'Up 2 days',
);

void main() {
  group('domain', () {
    test('kubectl pods get their own group, never a compose stack', () {
      final groups = groupContainersByCompose([_docker, _pod]);
      expect(groups.map((g) => g.label), [kStandaloneGroup, kPodsGroup]);
      expect(groups.last.rows.single.names, 'nginx-7b8b87776c-6qfpt');
      expect(isKubernetesPodRow(_pod), isTrue);
      expect(isKubernetesPodRow(_docker), isFalse);
      // A crictl container (engine crictl) is still a container row.
      expect(
        isKubernetesPodRow(
          const ContainerRow(
            id: 'x',
            names: 'x',
            image: 'x',
            state: 'running',
            status: 'Running',
            engine: 'crictl',
          ),
        ),
        isFalse,
      );
    });

    test('pod row maps to a pod workload and kubectl-aware facts', () {
      final w = podWorkloadFromRow(_pod);
      expect(w.kind, K8sKind.pod);
      expect(w.namespace, 'default');
      expect(w.name, 'nginx-7b8b87776c-6qfpt');
      expect(w.readyLabel, '1/1');

      // Cached facts from before schema 25 have no runtimes.
      final f = factsForPodRow(HostFacts.undiscovered, _pod);
      expect(kubectlFlavor(f), KubectlFlavor.kubectl);
      final k3s = factsForPodRow(
        HostFacts.undiscovered,
        const ContainerRow(
          id: 'a/b',
          names: 'b',
          namespace: 'a',
          image: 'x',
          state: 'running',
          status: 'Running',
          engine: 'k3s',
        ),
      );
      expect(kubectlFlavor(k3s), KubectlFlavor.k3s);
      // Facts that already know kubectl are left alone.
      final known = HostFacts.undiscovered.copyWith(runtimes: const ['k3s']);
      expect(identical(factsForPodRow(known, _pod), known), isTrue);
    });
  });

  testWidgets('tapping a pod opens the Kubernetes workload screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'k8s',
      address: '192.168.1.50',
      port: 22,
      username: 'hendra',
    );
    final pool = _Pool(repository: repo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          enrollmentProvider.overrideWith(ReadyEnrollment.new),
        ],
        child: KelolaApp(home: ContainersScreen(hostId: host.id)),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.text('KUBERNETES PODS'), findsOneWidget);
    // Pods are not a compose stack: no Up / Down actions.
    expect(find.text('Up'), findsNothing);
    expect(find.text('Down'), findsNothing);

    await tester.tap(find.text('default/nginx-7b8b87776c-6qfpt'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(WorkloadDetailScreen), findsOneWidget);
    final describe =
        pool.probes.whereType<WorkloadDescribeProbe>().single;
    expect(describe.kind, K8sKind.pod);
    expect(describe.namespace, 'default');
    expect(describe.name, 'nginx-7b8b87776c-6qfpt');
    // The docker/podman inspect path is never used for a pod.
    expect(pool.probes.whereType<ContainerInspectProbe>(), isEmpty);
    // kubectl was resolved even though cached facts had no runtimes.
    expect(
      describe.command(pool.factsSeen.last),
      contains("describe 'pod/nginx-7b8b87776c-6qfpt'"),
    );
  });
}

class _Pool extends SshSessionPool {
  _Pool({required super.repository})
      : super(
          signer: NoSshSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  final probes = <Probe<dynamic>>[];
  final factsSeen = <HostFacts>[];

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
    ProbeScope scope = ProbeScope.host,
    List<int>? stdinBytes,
  }) async {
    probes.add(probe);
    if (facts != null) {
      factsSeen.add(facts);
    }
    if (probe is HostFactsProbe) {
      return HostFacts.undiscovered as T;
    }
    if (probe is ContainerListProbe) {
      return const ContainerInventory(rows: [_docker, _pod]) as T;
    }
    if (probe is WorkloadDescribeProbe) {
      return 'Name: nginx-7b8b87776c-6qfpt' as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}
