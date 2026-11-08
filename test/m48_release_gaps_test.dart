import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/hosts/coreos_ack_store.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/domain/containers/container_list_parser.dart';
import 'package:kelola/domain/containers/container_list_view.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/coreos_node.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/presentation/coreos_notice_gate.dart';
import 'package:kelola/presentation/host_inventory_ping.dart';

import 'support/fakes.dart';

HostFacts _facts(String osId, [List<String> runtimes = const []]) =>
    HostFacts.undiscovered.copyWith(osId: osId, runtimes: runtimes);

void main() {
  // ---- Fix 1: no SSH to an unacknowledged OpenShift/OKD node ------------
  group('first-connect notice gate', () {
    test('pending only for a CoreOS node that is not acknowledged', () {
      for (final id in ['rhcos', 'scos', 'fcos']) {
        expect(coreOsNoticePending(_facts(id), acknowledged: false), isTrue,
            reason: id);
        expect(coreOsNoticePending(_facts(id), acknowledged: true), isFalse,
            reason: id);
      }
      expect(coreOsNoticePending(_facts('rhel'), acknowledged: false), isFalse);
      expect(coreOsNoticePending(HostFacts.undiscovered, acknowledged: false),
          isFalse);
    });

    test('coreOsNoticeBlocks reads the ack store only for CoreOS nodes',
        () async {
      var opened = 0;
      final store = CoreOsAckStore.memory();
      Future<CoreOsAckStore> acks() async {
        opened++;
        return store;
      }

      expect(await coreOsNoticeBlocks(_facts('debian'), 'h', acks), isFalse);
      expect(opened, 0, reason: 'no store read for an ordinary host');

      expect(await coreOsNoticeBlocks(_facts('rhcos'), 'h', acks), isTrue);
      await store.acknowledge('h');
      expect(await coreOsNoticeBlocks(_facts('rhcos'), 'h', acks), isFalse);
      expect(opened, 2);
    });

    test('an unreadable ack store blocks (fails safe)', () async {
      expect(
        await coreOsNoticeBlocks(
          _facts('scos'),
          'h',
          () async => throw StateError('no dir'),
        ),
        isTrue,
      );
      expect(await coreOsNoticeBlocks(_facts('fcos'), 'h', null), isTrue);
    });
  });

  group('Hosts screen inventory ping', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late _Pool pool;
    late Host host;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      pool = _Pool(repository: repo);
      host = await repo.insert(
        alias: 'crc-node',
        address: '192.168.130.11',
        port: 22,
        username: 'core',
      );
    });

    tearDown(() => db.close());

    test('cached unacknowledged node: no SSH at all', () async {
      await repo.saveFacts(host.id, _facts('rhcos'));
      final ping = await probeInventoryHost(
        pool: pool,
        repo: repo,
        host: host,
        noticePending: (f) async => f.isCoreOsNode,
      );
      expect(ping, isNull);
      expect(pool.kinds, isEmpty);
    });

    test('first discovery of a node stops after the facts read', () async {
      pool.facts = _facts('scos');
      final ping = await probeInventoryHost(
        pool: pool,
        repo: repo,
        host: host,
        noticePending: (f) async => f.isCoreOsNode,
      );
      expect(ping, isNull);
      expect(pool.kinds, [HostFactsProbe]);
    });

    test('acknowledged node and ordinary hosts still ping', () async {
      await repo.saveFacts(host.id, _facts('rhcos'));
      final ping = await probeInventoryHost(
        pool: pool,
        repo: repo,
        host: host,
        noticePending: (f) async => false,
      );
      expect(ping, isNotNull);
      expect(pool.kinds, [DashboardProbe]);
    });
  });

  // ---- Fix 2: existing hosts pick up oc ---------------------------------
  group('Kubernetes tool rediscovery', () {
    test('facts without any Kubernetes CLI are re-checked', () {
      expect(factsNeedK8sRediscovery(HostFacts.undiscovered), isTrue);
      expect(factsNeedK8sRediscovery(_facts('rhel', ['podman'])), isTrue);
      for (final cli in ['oc', 'k3s', 'kubectl']) {
        expect(factsNeedK8sRediscovery(_facts('rhel', [cli, 'podman'])),
            isFalse,
            reason: cli);
      }
    });
  });

  // ---- Fix 4: Containers screen lists pods through oc --------------------
  group('Containers pods via oc', () {
    test('probe looks for oc on PATH and at the CRC path, oc first', () {
      final cmd = const ContainerListProbe().command(HostFacts.undiscovered);
      expect(cmd, contains('command -v k3s kubectl oc docker podman crictl nerdctl'));
      expect(cmd, contains(r'[ -x "$HOME/.crc/bin/oc/oc" ] && echo "$HOME/.crc/bin/oc/oc"'));
      final pods = cmd.substring(cmd.indexOf('---PODS---'), cmd.indexOf('---PS_DOCKER---'));
      expect(pods.indexOf('oc'), lessThan(pods.indexOf('k3s')));
      expect(pods, contains(r'"$HOME/.crc/bin/oc/oc"'));
      expect(pods, contains('get pods -A'));
    });

    test('pods found through oc are pod rows that open with oc', () {
      final inv = const ContainerListParser().parse([
        '---ENGINE---',
        '/home/hendra/.crc/bin/oc/oc',
        '/usr/bin/podman',
        '---PODS---',
        'openshift-console\tconsole-7c9\tRunning\tquay.io/openshift/console',
        'demo\tweb-1\tRunning\tnginx:1.27',
        '---PS_DOCKER---',
        '---PS_PODMAN---',
        '---PS---',
      ].join('\n'));
      final pods = inv.rows.where(isKubernetesPodRow).toList();
      expect(pods.map((r) => r.names), ['console-7c9', 'web-1']);
      expect(pods.map((r) => r.engine).toSet(), {'oc'});
      final facts = factsForPodRow(HostFacts.undiscovered, pods.first);
      expect(kubectlFlavor(facts), KubectlFlavor.oc);
    });

    test('docker before the CRC oc in ENGINE still labels pods oc', () {
      final inv = const ContainerListParser().parse([
        '---ENGINE---',
        '/usr/bin/docker',
        '/home/hendra/.crc/bin/oc/oc',
        '---PODS---',
        'cli=oc',
        'demo\tweb-1\tRunning\tnginx:1.27',
        '---PS_DOCKER---',
        '---PS---',
      ].join('\n'));
      final pod = inv.rows.where(isKubernetesPodRow).single;
      expect(pod.engine, 'oc');
      expect(kubectlFlavor(factsForPodRow(HostFacts.undiscovered, pod)),
          KubectlFlavor.oc);
    });

    test('each pod branch names the CLI it used', () {
      final cmd = const ContainerListProbe().command(HostFacts.undiscovered);
      for (final cli in ['oc', 'k3s', 'kubectl']) {
        expect(cmd, contains('echo "cli=$cli"'), reason: cli);
      }
    });

    test('kubectl and k3s pods keep their labels', () {
      ContainerRow pod(String engineLine) => const ContainerListParser()
          .parse('---ENGINE---\n$engineLine\n---PODS---\ndefault\tp\tRunning\tx\n---PS---\n')
          .rows
          .single;
      expect(pod('/usr/bin/kubectl').engine, 'k8s');
      expect(pod('/usr/local/bin/k3s').engine, 'k3s');
    });

    test('pod inspect can use oc', () {
      const row = ContainerRow(
        id: 'demo/web-1',
        names: 'web-1',
        image: 'nginx',
        state: 'running',
        status: 'Running',
        engine: 'oc',
        namespace: 'demo',
      );
      final cmd = const ContainerActionProbe(row: row, verb: ContainerVerb.inspect)
          .command(HostFacts.undiscovered);
      expect(cmd, contains(r'"$(command -v oc || echo "$HOME/.crc/bin/oc/oc")"'));
      expect(cmd, contains("describe pod 'web-1'"));
    });
  });
}

class _Pool extends SshSessionPool {
  _Pool({required super.repository})
      : super(
          signer: NoSshSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  HostFacts facts = HostFacts.undiscovered;
  final kinds = <Type>[];
  final hostIds = <String>[];

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
    kinds.add(probe.runtimeType);
    if (probe is HostFactsProbe) {
      return this.facts as T;
    }
    if (probe is DashboardProbe) {
      return const DashboardSnapshot(
        uptime: Duration(hours: 1),
        load1: 0.1,
        cpuPercent: 1,
        memUsedPercent: 20,
        diskRootPercent: 40,
        failedUnitCount: 0,
        failedUnitNames: [],
      ) as T;
    }
    if (probe is FleetHealthProbe) {
      hostIds.add(host.id);
      return FleetHostHealth(
        hostId: host.id,
        alias: host.alias,
        reachable: true,
        load1: 0.1,
        nprocCores: 2,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 11, 5),
      ) as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}
