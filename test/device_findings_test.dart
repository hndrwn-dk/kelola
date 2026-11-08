import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/llm/openai_client.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/app_lock/app_lock_timeout.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_home_summary.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/llm/explain_sections.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';
import 'package:kelola/domain/snippets/snippet_multi.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';

K8sWorkload _pod({
  String namespace = 'default',
  String name = 'p',
  int ready = 1,
  int desired = 1,
  HealthStatus health = HealthStatus.warning,
  String podPhase = 'Running',
  int restarts = 7,
}) {
  return K8sWorkload(
    kind: K8sKind.pod,
    namespace: namespace,
    name: name,
    ready: ready,
    desired: desired,
    phase: 'Running · last exit unknown',
    health: health,
    restarts: restarts,
    podPhase: podPhase,
  );
}

void main() {
  group('password during the host-key fingerprint prompt', () {
    test('the fingerprint dialog taking focus keeps the password', () {
      expect(
        lifecycleClearsPassword(
          AppLifecycleState.inactive,
          hostKeyPromptOpen: true,
        ),
        isFalse,
      );
    });

    test('leaving the app during the prompt still wipes it', () {
      expect(
        lifecycleClearsPassword(
          AppLifecycleState.paused,
          hostKeyPromptOpen: true,
        ),
        isTrue,
      );
    });

    test('losing focus outside the prompt still wipes it', () {
      expect(
        lifecycleClearsPassword(
          AppLifecycleState.inactive,
          hostKeyPromptOpen: false,
        ),
        isTrue,
      );
      expect(
        lifecycleClearsPassword(
          AppLifecycleState.resumed,
          hostKeyPromptOpen: false,
        ),
        isFalse,
      );
    });
  });

  group('restarts are not readiness', () {
    test('a running ready pod with many restarts is ready but flagged', () {
      final pod = _pod();
      expect(pod.notReady, isFalse);
      expect(pod.readyButRestarting, isTrue);
      expect(pod.restarting, isTrue);
    });

    test('a running pod missing a ready container stays not ready', () {
      final pod = _pod(ready: 0);
      expect(pod.notReady, isTrue);
      expect(pod.readyButRestarting, isFalse);
    });

    test('a pending pod stays not ready', () {
      final pod = _pod(ready: 0, podPhase: 'Pending', restarts: 0);
      expect(pod.notReady, isTrue);
    });

    test('home counts them as restarting and still lists them', () {
      final summary = WorkloadHomeSummary.from([
        _pod(name: 'a'),
        _pod(name: 'b', ready: 0),
      ]);
      expect(summary.notReadyCount, 1);
      expect(summary.restartingCount, 2);
      expect(summary.worst.map((r) => r.name), ['b', 'a']);
    });

    test('CoreDNS with lifetime restarts is ready', () {
      final dns = _pod(namespace: 'kube-system', name: 'coredns-1');
      expect(coreDnsReadyFromWorkloads([dns]), isTrue);
    });

    test('CoreDNS missing a ready container is not ready', () {
      final dns = _pod(namespace: 'kube-system', name: 'coredns-1', ready: 0);
      expect(coreDnsReadyFromWorkloads([dns]), isFalse);
    });
  });

  group('a cluster we could not read', () {
    test('never claims workloads are ready', () {
      expect(
        workloadsAllClearLine(apiReachable: false, rows: 0),
        'Could not read workloads',
      );
      expect(
        workloadsAllClearLine(apiReachable: true, rows: 0),
        'No workloads listed',
      );
      expect(
        workloadsAllClearLine(apiReachable: true, rows: 3),
        'All listed workloads ready',
      );
    });

    test('an unreadable k3s kubeconfig is not an unreachable API', () {
      const stdout = '---HOSTNAME---\n'
          'node\n'
          '---READYZ---\n'
          '---READYZ_FAIL---\n'
          '---NODES---\n'
          '---AUTH---\n'
          'time="x" level=warning msg="Unable to read '
          '/etc/rancher/k3s/k3s.yaml, please start server with '
          '--write-kubeconfig-mode"\n';
      final cluster = parseClusterHealth(stdout);
      expect(cluster.apiReachable, isFalse);
      expect(cluster.kubeconfigDenied, isTrue);
      expect(cluster.apiLabel, 'no kubeconfig access');
      expect(cluster.withCoreDns(true).kubeconfigDenied, isTrue);
    });

    test('a plain readyz failure still reads unreachable', () {
      const stdout = '---HOSTNAME---\n'
          'node\n'
          '---READYZ---\n'
          '---READYZ_FAIL---\n'
          '---NODES---\n'
          '---AUTH---\n'
          'The connection to the server localhost:6443 was refused\n';
      final cluster = parseClusterHealth(stdout);
      expect(cluster.kubeconfigDenied, isFalse);
      expect(cluster.apiLabel, 'unreachable');
    });
  });

  test('firewall empty state is not shown under an error', () {
    final src =
        File('lib/presentation/screens/firewall_screen.dart').readAsStringSync();
    expect(src, contains('rules.isEmpty && !_loading && _error == null'));
  });

  group('dashboard pending updates', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late String hostId;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      final host = await repo.insert(
        alias: 'h',
        address: '10.0.0.1',
        port: 22,
        username: 'u',
      );
      hostId = host.id;
    });

    tearDown(() => db.close());

    test('unknown until a package list was read', () async {
      expect(await repo.knownPendingUpdates(hostId), isNull);
    });

    test('a read list is the answer, including zero', () async {
      await repo.savePackageListCache(
        hostId: hostId,
        snapshot: const PackageSnapshot(
          manager: PackageManager.apt,
          updates: [],
          rebootRequired: false,
        ),
      );
      expect(await repo.knownPendingUpdates(hostId), 0);
    });
  });

  test('terminal audit rows finish, so they never read as interrupted', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, contains('final auditId = await _repository.beginAudit('));
    final open = AuditEvent(
      id: 'a',
      timestampUtc: DateTime.utc(2026),
      hostId: 'h',
      hostAlias: 'h',
      remoteUser: 'u',
      title: 'Opened terminal',
      command: 'pty',
      risk: 'mutate',
      usedSudo: false,
      durationMs: 0,
      appVersion: '',
      exitCode: 0,
    );
    expect(open.orphan, isFalse);
  });

  group('OpenAI-compatible base URLs', () {
    test('a versioned base is not versioned twice', () {
      expect(openAiCompletionsPath('/v1'), '/v1/chat/completions');
      expect(openAiCompletionsPath('/v1/'), '/v1/chat/completions');
      expect(openAiCompletionsPath('/api/v2'), '/api/v2/chat/completions');
    });

    test('an unversioned base gains v1', () {
      expect(openAiCompletionsPath(''), '/v1/chat/completions');
      expect(openAiCompletionsPath('/'), '/v1/chat/completions');
      expect(openAiCompletionsPath('/proxy'), '/proxy/v1/chat/completions');
    });
  });

  test('Explain labels with the colon inside bold leave no markers', () {
    final parsed = parseExplainSections(
      '**Cause:** bad directive\n**Next Step:** run nginx -t',
      kind: ExplainKind.failedUnit,
    );
    expect(parsed.isStructured, isTrue);
    expect(parsed.sections.first.title, 'Cause');
    expect(parsed.sections.first.body, 'bad directive');
    expect(parsed.sections.last.body, 'run nginx -t');
  });

  test('a line with no timestamp shows none, not the epoch', () {
    const entry = JournalEntry(
      cursor: 'unit-detail-0',
      realtimeUsec: '',
      priority: 3,
      message: 'x',
    );
    expect(entry.timestamp, isNull);
    final src = File('lib/domain/incident/correlation.dart').readAsStringSync();
    expect(src, isNot(contains("realtimeUsec: '0'")));
  });

  group('screenshots', () {
    test('App lock blocks them unless allowed', () {
      expect(recentsSecure(-1), isTrue);
      expect(recentsSecure(-1, allowScreenshots: true), isFalse);
      expect(recentsSecure(0), isFalse);
    });

    test('allowing them keeps the Recents preview hidden under App lock', () {
      expect(recentsPreviewHidden(-1, allowScreenshots: true), isTrue);
      expect(recentsPreviewHidden(-1, allowScreenshots: false), isFalse);
      expect(recentsPreviewHidden(0, allowScreenshots: true), isFalse);
    });

    test('the Allowed choice warns about the app switcher', () {
      final src =
          File('lib/presentation/screens/settings_screen.dart').readAsStringSync();
      expect(src, contains('Below Android 13 and on iOS'));
      expect(src, contains('app switcher while locked'));
    });

    test('the choice persists and defaults to blocked', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      expect(await repo.allowScreenshots(), isFalse);
      await repo.setAllowScreenshots(true);
      expect(await repo.allowScreenshots(), isTrue);
    });
  });

  group('selecting hosts by tag', () {
    Host host(String id, List<String> tags) => Host(
          id: id,
          alias: id,
          address: '10.0.0.1',
          port: 22,
          username: 'u',
          keyAlias: 'k',
          tags: tags,
        );

    test('tags are distinct and sorted', () {
      final hosts = [
        host('a', ['uat', 'east']),
        host('b', ['prod', 'east']),
      ];
      expect(snippetMultiTags(hosts), ['east', 'prod', 'uat']);
    });

    test('a tag selects its hosts and null selects all', () {
      final hosts = [
        host('a', ['uat']),
        host('b', ['prod']),
      ];
      expect(snippetMultiSelectTag(hosts, 'prod'), {'b'});
      expect(snippetMultiSelectTag(hosts, null), {'a', 'b'});
    });
  });

  test('a saved target with a live tunnel cannot start twice', () {
    const target = TunnelTarget(
      id: 't1',
      hostId: 'h1',
      label: 'Cockpit',
      remoteHost: '127.0.0.1',
      remotePort: 9090,
      scheme: TunnelScheme.https,
      path: '/',
    );
    ActiveTunnel tunnel(TunnelState state) => ActiveTunnel(
          id: 'a',
          target: target,
          hostAlias: 'h',
          localPort: 4242,
          state: state,
          openedAtUtc: DateTime.utc(2026),
          openChannels: 0,
        );
    expect(tunnelTargetRunning(target, [tunnel(TunnelState.listening)]), isTrue);
    expect(tunnelTargetRunning(target, [tunnel(TunnelState.failed)]), isFalse);
    expect(tunnelTargetRunning(target, const []), isFalse);
  });
}
