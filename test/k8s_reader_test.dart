import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/k8s_reader_probes.dart';
import 'package:kelola/domain/probes/workload_logs_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/domain/probes/workload_yaml_probe.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/presentation/widgets/k8s_reader_flow.dart';

HostFacts _facts(List<String> runtimes) =>
    HostFacts.undiscovered.copyWith(runtimes: runtimes);

final _k3s = _facts(['k3s']);
final _kubectl = _facts(['kubectl']);
final _oc = _facts(['oc', 'kubectl']);

const _reader = r'"$HOME/.kube/kelola.yaml"';

const _workload = K8sWorkload(
  kind: K8sKind.deployment,
  namespace: 'shop',
  name: 'web',
  ready: 1,
  desired: 1,
);

void main() {
  group('role and manifest', () {
    test('the role grants get and list only, never a forbidden resource', () {
      for (final rule in kelolaReaderRules) {
        expect(rule.verbs, ['get', 'list'], reason: '${rule.resources}');
        expect(rule.apiGroups, isNot(contains('*')));
        for (final r in rule.resources) {
          expect(kelolaReaderForbiddenResources, isNot(contains(r)), reason: r);
          expect(r, isNot(contains('*')));
          // No subresource but logs: exec, attach, portforward, proxy, token.
          if (r.contains('/')) expect(r, 'pods/log');
        }
      }
    });

    test('the role covers what the reader probes read', () {
      final granted = {
        for (final r in kelolaReaderRules)
          for (final res in r.resources)
            '${r.apiGroups.single.isEmpty ? '' : '${r.apiGroups.single}/'}$res',
      };
      for (final needed in [
        'nodes',
        'events',
        'events.k8s.io/events',
        'services',
        'endpoints',
        'discovery.k8s.io/endpointslices',
        'persistentvolumes',
        'persistentvolumeclaims',
        'pods',
        'pods/log',
        'serviceaccounts',
        'apps/deployments',
        'apps/statefulsets',
        'apps/daemonsets',
        'batch/jobs',
        'batch/cronjobs',
        'networking.k8s.io/networkpolicies',
        'rbac.authorization.k8s.io/clusterrolebindings',
        'metrics.k8s.io/pods',
        'metrics.k8s.io/nodes',
        'argoproj.io/applications',
        'argoproj.io/applicationsets',
        'argoproj.io/appprojects',
      ]) {
        expect(granted, contains(needed), reason: needed);
      }
    });

    test('argo rule is read-only and names no secrets', () {
      final argo = kelolaReaderRules.where(
        (r) => r.apiGroups.contains('argoproj.io'),
      );
      expect(argo, hasLength(1));
      expect(argo.single.verbs, ['get', 'list']);
      expect(argo.single.resources, [
        'applications',
        'applicationsets',
        'appprojects',
      ]);
      expect(kelolaReaderManifest(), contains('apiGroups: ["argoproj.io"]'));
    });

    test('the manifest names the four objects with Kelola labels', () {
      final m = kelolaReaderManifest();
      final docs = m.split('\n---\n');
      expect(docs, hasLength(4));
      expect(docs[0], contains('kind: Namespace\nmetadata:\n  name: kelola'));
      expect(docs[1], contains('kind: ServiceAccount'));
      expect(docs[1], contains('automountServiceAccountToken: false'));
      expect(docs[2], contains('kind: ClusterRole\n'));
      expect(docs[3], contains('kind: ClusterRoleBinding'));
      expect(docs[3], contains('  kind: ClusterRole\n  name: kelola-reader'));
      for (final d in docs) {
        expect(d, contains('app.kubernetes.io/managed-by: kelola'));
        expect(d, contains('app.kubernetes.io/name: kelola-reader'));
      }
      final verbs = RegExp(r'verbs: \[(.*)\]').allMatches(m).map((x) => x[1]);
      expect(verbs.toSet(), {'"get", "list"'});
      for (final word in [
        'secrets',
        'configmaps',
        'exec',
        'attach',
        'portforward',
        'proxy',
        'watch',
        '"*"',
      ]) {
        expect(m, isNot(contains(word)), reason: word);
      }
      final resources = RegExp(r'resources: \[(.*)\]')
          .allMatches(m)
          .expand((x) => x[1]!.split(', '))
          .map((r) => r.replaceAll('"', ''));
      expect(resources, isNotEmpty);
      for (final r in resources) {
        expect(kelolaReaderForbiddenResources, isNot(contains(r)), reason: r);
      }
    });

    test('the review sheet lists exactly the applied objects and rules', () {
      final lines = k8sReaderPreviewLines();
      for (final o in kelolaReaderObjectLines) {
        expect(lines, contains(o));
      }
      for (final r in kelolaReaderRuleLines()) {
        expect(lines, contains('  $r'));
      }
      expect(
        lines,
        contains(
          '  core: nodes, namespaces, events, services, '
          'endpoints, persistentvolumes, persistentvolumeclaims, pods, '
          'pods/log, serviceaccounts',
        ),
      );
      expect(lines.join('\n'), contains('90 days'));
      expect(lines.join('\n'), contains('~/.kube/kelola.yaml (mode 0600)'));
    });

    test('only k3s and kubectl get a reader; oc keeps its login', () {
      expect(kelolaReaderSupported(KubectlFlavor.k3s), isTrue);
      expect(kelolaReaderSupported(KubectlFlavor.kubectl), isTrue);
      expect(kelolaReaderSupported(KubectlFlavor.oc), isFalse);
      expect(kelolaReaderSupported(KubectlFlavor.none), isFalse);
      expect(
        () => buildK8sReaderSetupScript(KubectlFlavor.oc),
        throwsArgumentError,
      );
      expect(k8sReaderPreviewNote(KubectlFlavor.oc), contains('own oc login'));
      expect(k8sReaderPreviewNote(KubectlFlavor.none), isNull);
      expect(
        k8sReaderPreviewNote(KubectlFlavor.k3s),
        allOf(
          contains('never Secrets'),
          contains('keep credentials in Secrets'),
        ),
      );
    });
  });

  group('setup script', () {
    for (final flavor in [KubectlFlavor.k3s, KubectlFlavor.kubectl]) {
      final script = buildK8sReaderSetupScript(flavor);

      test(
        '${flavor.name}: the password comes from stdin and is only piped',
        () {
          expect(
            script,
            startsWith('set -u\nIFS= read -r SUDO_PASS || true\n'),
          );
          final uses = RegExp(r'\$SUDO_PASS|\$\{SUDO_PASS').allMatches(script);
          // The one pipe into `sudo -S`, never an argument.
          expect(uses, hasLength(1));
          expect(
            script,
            contains(
              "asroot() { printf '%s\\n' \"\$SUDO_PASS\" | sudo -S -p '' \"\$@\"; }",
            ),
          );
          expect(script, contains('unset SUDO_PASS TOKOUT TOKEN'));
        },
      );

      test('${flavor.name}: the token is never echoed, logged or in argv', () {
        final lines = script.split('\n');
        for (final l in lines.where(
          (l) =>
              l.contains(r'$TOKEN') ||
              l.contains(r'${TOKOUT') ||
              l.contains(r'$TOKOUT'),
        )) {
          final ok =
              l.contains(
                r"printf '    token: %s\n' "
                '"\$TOKEN"',
              ) ||
              l.contains(r'case "$TOKEN" in') ||
              l.contains(r'case "$TOKOUT" in') ||
              l.contains(r'EXP=${TOKOUT%%"$nl"*}; TOKEN=${TOKOUT#*"$nl"}');
          expect(ok, isTrue, reason: l);
        }
        expect(script, isNot(contains('echo "\$TOKEN')));
        expect(script, isNot(contains('--token')));
        expect(script, isNot(contains('set -x')));
        // The token step's stderr is dropped.
        for (final l in lines.where((l) => l.contains('create token'))) {
          expect(l, contains('2>/dev/null'), reason: l);
        }
      });

      test('${flavor.name}: kubeconfig is written 0600 under a 077 umask', () {
        expect(script, contains('umask 077\n'));
        expect(
          script,
          contains(r'chmod 600 -- "$NEW" && mv -f -- "$NEW" "$CFG"'),
        );
        expect(script, contains(r'CFG="$HOME/.kube/kelola.yaml"'));
        expect(script, contains(r'mkdir -m 700 -- "$HOME/.kube"'));
        expect(script, contains('--duration=$kelolaReaderTokenDuration'));
        expect(kelolaReaderTokenDuration, '2160h');
      });

      test('${flavor.name}: admin credentials are root files, then own', () {
        for (final f in kelolaReaderAdminConfigs(flavor)) {
          expect(script, contains(f));
        }
        expect(script, contains('--kubeconfig="\$ADMINCFG"'));
        expect(script, contains('auth can-i create clusterrolebindings'));
        expect(script, contains('say noadmin'));
        expect(script, contains('say unreachable'));
        expect(script, contains('say noca'));
        // A login-writable or non-root CLI is never run as root.
        expect(script, contains('if ! rootowned "\$CLI_BIN"; then say nocli'));
      });

      test('${flavor.name}: refuses objects Kelola did not label', () {
        expect(script, contains(r'*/kelola) ;; *) say conflict'));
      });
    }

    test('the remove script deletes by label only', () {
      final s = buildK8sReaderRemoveScript(KubectlFlavor.k3s);
      expect(
        s,
        contains(
          'admin delete clusterrolebinding,clusterrole,namespace '
          '--selector=app.kubernetes.io/name=kelola-reader,'
          'app.kubernetes.io/managed-by=kelola --wait=false',
        ),
      );
      expect(s, contains(r'rm -f -- "$HOME/.kube/kelola.yaml"'));
      expect(s, isNot(contains('delete namespace kelola')));
    });

    test('audit rows name the step, never the script or a token', () {
      const setup = K8sReaderSetupProbe();
      expect(
        setup.auditCommand(_k3s),
        'kelola-k8s-reader-setup k3s kelola/kelola-reader duration=2160h '
        '~/.kube/kelola.yaml',
      );
      expect(setup.risk, RiskLevel.mutate);
      expect(
        const K8sReaderRemoveProbe().auditCommand(_kubectl),
        'kelola-k8s-reader-remove kubectl kelola/kelola-reader '
        '~/.kube/kelola.yaml',
      );
    });
  });

  group('output parsers', () {
    test('setup markers', () {
      final r = parseK8sReaderOutput(
        'noise\nKELOLA_K8S_READER=ok\n'
        'KELOLA_K8S_READER_VIA=/etc/rancher/k3s/k3s.yaml\n'
        'KELOLA_K8S_READER_EXP=2027-02-20T10:00:00Z\n',
      );
      expect(r.outcome, K8sReaderOutcome.ok);
      expect(r.via, '/etc/rancher/k3s/k3s.yaml');
      expect(r.expires, DateTime.utc(2027, 2, 20, 10));
    });

    test('failures, junk and nothing at all never throw', () {
      expect(
        parseK8sReaderOutput(
          'KELOLA_K8S_READER=failed\nKELOLA_K8S_READER_STEP=token\n',
        ).step,
        'token',
      );
      for (final (out, want) in [
        ('KELOLA_K8S_READER=noadmin', K8sReaderOutcome.noAdmin),
        ('KELOLA_K8S_READER=nocli', K8sReaderOutcome.noCli),
        ('KELOLA_K8S_READER=unreachable', K8sReaderOutcome.unreachable),
        ('KELOLA_K8S_READER=conflict', K8sReaderOutcome.conflict),
        ('KELOLA_K8S_READER=noca', K8sReaderOutcome.noCa),
        ('KELOLA_K8S_READER=removed', K8sReaderOutcome.removed),
        ('KELOLA_K8S_READER=what', K8sReaderOutcome.unknown),
        ('', K8sReaderOutcome.unknown),
        ('\u0000ÿ{]', K8sReaderOutcome.unknown),
      ]) {
        expect(parseK8sReaderOutput(out).outcome, want, reason: out);
      }
      expect(
        parseK8sReaderOutput('KELOLA_K8S_READER=ok\nKELOLA_K8S_READER_EXP=soon')
            .expires,
        isNull,
      );
    });

    test('status reads the expiry comment only', () {
      expect(k8sReaderStatusCommand, isNot(contains('token')));
      expect(
        k8sReaderStatusCommand,
        contains("sed -n 's/^# kelola-expires: //p'"),
      );
      final s = parseK8sReaderStatus(
        '2027-02-20T10:00:00Z\nKELOLA_K8S_READER_PRESENT\n',
      );
      expect(s.present, isTrue);
      expect(s.expires, DateTime.utc(2027, 2, 20, 10));
      expect(s.expiredAt(DateTime.utc(2027, 3)), isTrue);
      expect(
        parseK8sReaderStatus('\nKELOLA_K8S_READER_PRESENT\n').expires,
        isNull,
      );
      expect(parseK8sReaderStatus('KELOLA_K8S_READER_PRESENT').present, isTrue);
      expect(parseK8sReaderStatus('KELOLA_K8S_READER_ABSENT').present, isFalse);
      expect(parseK8sReaderStatus('junk').present, isFalse);
      expect(
        const K8sReaderStatusProbe().command(_oc),
        'echo KELOLA_K8S_READER_ABSENT',
      );
    });
  });

  group('probe argv', () {
    test('kubectlRead tries the reader kubeconfig, then today\'s read', () {
      expect(
        kubectlRead(_kubectl, 'get nodes --output=json'),
        '[ -r $_reader ] && LC_ALL=C kubectl --kubeconfig=$_reader '
        'get nodes --output=json 2>/dev/null || '
        'kubectl get nodes --output=json 2>/dev/null || '
        'sudo -n kubectl get nodes --output=json',
      );
      expect(
        kubectlRead(_k3s, 'get nodes'),
        '[ -r $_reader ] && LC_ALL=C k3s kubectl --kubeconfig=$_reader '
        'get nodes 2>/dev/null || '
        'sudo -n k3s kubectl get nodes 2>/dev/null || k3s kubectl get nodes',
      );
      // oc and no CLI: unchanged.
      expect(kubectlRead(_oc, 'get nodes'), kubectlTry(_oc, 'get nodes'));
      expect(kubectlRead(_facts([]), 'x'), 'echo ---NO_KUBECTL---');
    });

    test('workload and pod lists ask the reader for named columns only', () {
      final cmd = const WorkloadListProbe().command(_k3s);
      final readerPart = cmd.split(' 2>/dev/null || ').first;
      expect(readerPart, contains('--kubeconfig=$_reader'));
      expect(readerPart, contains('--output=custom-columns='));
      expect(readerPart, isNot(contains('--output=json')));
      // Today's read is unchanged after it.
      expect(
        cmd,
        contains(
          'sudo -n k3s kubectl get deploy,sts,ds,job,cronjob,pod --all-namespaces --output=json',
        ),
      );

      final pods = const ContainerListProbe().command(_k3s);
      final line = pods
          .split('\n')
          .firstWhere(
            (l) => l.contains('--kubeconfig="\$HOME/.kube/kelola.yaml"'),
          );
      expect(
        line,
        contains('get pods --all-namespaces \'--output=custom-columns='),
      );
      expect(line.split(' 2>/dev/null; }').first, isNot(contains('jsonpath')));
    });

    test('reads that print pod templates or config stay off the reader', () {
      for (final cmd in [
        const WorkloadDescribeProbe(
          kind: K8sKind.deployment,
          namespace: 'shop',
          name: 'web',
        ).command(_k3s),
        const WorkloadYamlGetProbe(workload: _workload).command(_k3s),
        const RolloutHistoryProbe().command(_k3s),
        const ConfigInventoryProbe().command(_k3s),
      ]) {
        expect(cmd, isNot(contains('kelola.yaml')), reason: cmd);
      }
    });

    test('cluster reads, events, top and logs use the reader', () {
      for (final cmd in [
        const ClusterHealthProbe().command(_kubectl),
        const ClusterEventsProbe().command(_kubectl),
        const ServiceListProbe().command(_kubectl),
        const StorageListProbe().command(_kubectl),
        const SecurityInventoryProbe().command(_kubectl),
        const WorkloadEventsProbe(
          namespace: 'shop',
          name: 'web',
        ).command(_kubectl),
        const WorkloadTopProbe(namespace: 'shop').command(_kubectl),
        const WorkloadLogsProbe(_workload).command(_kubectl),
      ]) {
        expect(cmd, contains('kubectl --kubeconfig=$_reader'), reason: cmd);
      }
      // The context names the login's own cluster, never the reader's.
      final health = const ClusterHealthProbe().command(_kubectl);
      expect(
        health,
        contains('echo ---CONTEXT---\nkubectl config current-context'),
      );
    });

    test('logs fall back when the reader token is refused', () {
      final cmd = kubectlOnceRead(_kubectl, 'logs x');
      expect(
        cmd,
        startsWith(
          '{ export LC_ALL=C; if [ -r $_reader ] && '
          'kubectl --kubeconfig=$_reader get --raw=/version >/dev/null 2>&1; '
          'then kubectl --kubeconfig=$_reader logs x; else { export LC_ALL=C; ',
        ),
      );
      expect(kubectlOnceRead(_oc, 'logs x'), kubectlOnce(_oc, 'logs x'));
    });

    test('mutating helpers never use the reader kubeconfig', () {
      for (final f in [_k3s, _kubectl, _oc]) {
        for (final cmd in [
          kubectlOnce(f, '-n a exec pod/x -- sh -c id'),
          kubectlRun(f, 'scale deploy/x --replicas=2'),
          kubectlTry(f, 'get x'),
          kubectlStdin(f, '-n a apply -f -', 'kind: X'),
          kubectlPortForwardCommand(f, resource: 'svc/a', port: 80),
        ]) {
          expect(cmd, isNot(contains('kelola.yaml')), reason: cmd);
        }
      }
    });

    test('source pin: no mutating probe names the reader', () {
      const mutating = [
        'lib/domain/probes/workload_action_probe.dart',
        'lib/domain/probes/workload_exec_probe.dart',
        'lib/domain/probes/workload_yaml_probe.dart',
        'lib/domain/probes/container_action_probe.dart',
        'lib/data/ssh/tunnel_manager.dart',
      ];
      for (final path in mutating) {
        final src = File(path).readAsStringSync();
        for (final banned in [
          'kubectlRead',
          'kubectlOnceRead',
          'kubectlReaderCli',
          'kelolaReaderKubeconfig',
          'kelola.yaml',
          'k8s_reader',
        ]) {
          expect(src, isNot(contains(banned)), reason: '$path: $banned');
        }
      }
      // Every reader user is a read probe.
      final users = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) {
            final src = f.readAsStringSync();
            return src.contains('kubectlRead(') ||
                src.contains('kubectlOnceRead(') ||
                src.contains('.kube/kelola.yaml');
          })
          .map((f) => f.path.replaceAll('\\', '/'))
          .toSet();
      expect(users, {
        'lib/domain/k8s/k8s_reader.dart',
        'lib/domain/k8s/kubectl.dart',
        'lib/domain/probes/argo_probes.dart',
        'lib/domain/probes/cluster_health_probe.dart',
        'lib/domain/probes/cluster_resource_probes.dart',
        'lib/domain/probes/container_list_probe.dart',
        'lib/domain/probes/workload_logs_probe.dart',
        'lib/domain/probes/workload_probes.dart',
      });
    });
  });

  group('PR #9 sudo rules are gone', () {
    test('no sudoers group or rule names a Kubernetes CLI', () {
      final names = KelolaSudoersGroup.values.map((g) => g.name);
      expect(names, isNot(contains('kubernetes')));
      for (final f in [
        _k3s,
        _kubectl,
        _facts(['k3s', 'crictl']),
      ]) {
        final spec = buildKelolaSudoersSpec(
          user: 'hendr',
          facts: f,
          groups: KelolaSudoersGroup.values.toSet(),
          sudo: const ClassicSudo(1, 9, 17),
        );
        for (final bin in ['k3s', 'kubectl', 'crictl', 'KELOLA_K8S_READS']) {
          expect(spec.content, isNot(contains(bin)), reason: bin);
        }
      }
      final src = File('lib/domain/k8s/kubectl.dart').readAsStringSync();
      expect(src, isNot(contains('--request-timeout=0')));
    });
  });

  group('copy', () {
    test('every outcome says what happened and keeps today\'s reads', () {
      for (final o in K8sReaderOutcome.values) {
        final notes = k8sReaderNotes(
          K8sReaderResult(outcome: o, step: 'apply'),
        );
        expect(notes, hasLength(1), reason: o.name);
        final text =
            '${notes.single.lead}${notes.single.path}${notes.single.tail}';
        if (o == K8sReaderOutcome.ok) {
          expect(text, contains('now use the read-only kelola-reader'));
        } else {
          expect(text, contains('your own kubeconfig'), reason: o.name);
        }
      }
      final ok = k8sReaderNotes(
        K8sReaderResult(
          outcome: K8sReaderOutcome.ok,
          expires: DateTime.utc(2027, 2, 20),
        ),
      ).single;
      expect(ok.path, '~/.kube/kelola.yaml');
      expect(ok.tail, '. Token until 20 Feb 2027.');
      expect(
        k8sReaderNotes(
          const K8sReaderResult(
            outcome: K8sReaderOutcome.failed,
            step: 'token',
          ),
        ).single.lead,
        contains('the token step failed'),
      );
    });

    test('status lines', () {
      final now = DateTime.utc(2026, 11, 22);
      expect(
        k8sReaderStatusLine(const K8sReaderStatus(present: false), now),
        contains('Enable Kelola sudo can set up'),
      );
      expect(
        k8sReaderStatusLine(
          K8sReaderStatus(present: true, expires: DateTime.utc(2027, 2, 20)),
          now,
        ),
        'Reads use the read-only kelola-reader account. Token until 20 Feb 2027.',
      );
      expect(
        k8sReaderStatusLine(
          K8sReaderStatus(present: true, expires: DateTime.utc(2026, 11, 1)),
          now,
        ),
        contains('expired on 1 Nov 2026'),
      );
    });

    testWidgets('access block: Set up alone, or Renew and Remove', (
      tester,
    ) async {
      var setUp = 0;
      var removed = 0;
      Future<void> pump(K8sReaderStatus s) => tester.pumpWidget(
        MaterialApp(
          theme: buildKelolaDarkTheme(),
          home: Scaffold(
            body: K8sReaderAccessBlock(
              status: s,
              now: DateTime.utc(2026, 11, 22),
              onSetUp: () => setUp++,
              onRemove: () => removed++,
            ),
          ),
        ),
      );
      await pump(const K8sReaderStatus(present: false));
      expect(find.text('Set up'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      await tester.tap(find.text('Set up'));
      expect(setUp, 1);

      await pump(
        K8sReaderStatus(present: true, expires: DateTime.utc(2027, 2, 20)),
      );
      expect(find.text('Renew'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      expect(removed, 1);
    });
  });

  // Runs the generated shell for real against fake sudo, kubectl and stat.
  // Windows has no POSIX PATH to fake.
  group('in a shell', skip: Platform.isWindows, () {
    late Directory dir;
    late Directory home;
    const pass = 's3cret-pass';
    const token = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJrZWxvbGEifQ.c2lnbmF0dXJl';

    File log() => File('${dir.path}/calls.log');

    void script(String name, String body) {
      final f = File('${dir.path}/bin/$name');
      if (f.existsSync()) Process.runSync('chmod', ['u+w', f.path]);
      f
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      // Not writable by the login: the setup's root-owned check.
      Process.runSync('chmod', ['555', f.path]);
    }

    /// Fake kubectl. [mode] picks the failure to simulate.
    void fakeKubectl({String mode = 'ok', String canI = 'no'}) {
      script('kubectl', '''
printf 'kubectl %s\\n' "\$*" >> "${log().path}"
args="\$*"
case "\$args" in
  *"kelola.yaml"*"can-i list pods"*) echo yes; exit 0 ;;
  *"kelola.yaml"*"can-i get secrets"*) echo no; exit 1 ;;
  *"auth can-i"*) echo $canI; [ $canI = yes ]; exit ;;
  *"get --raw=/version"*) [ "$mode" = unreachable ] && exit 1; echo '{}'; exit 0 ;;
  *"--ignore-not-found"*)
    [ "$mode" = conflict ] && case "\$args" in *namespace/kelola*) echo 'kelola/'; esac
    exit 0 ;;
  *"apply --filename="*)
    f=\${args##*--filename=}; cp "\$f" "${dir.path}/applied.yaml"; exit 0 ;;
  *"create token"*"--output=jsonpath"*)
    [ "$mode" = nojsonpath ] && { echo "unknown flag: --output" >&2; exit 1; }
    [ "$mode" = badtoken ] && { printf '2027-02-20T10:00:00Z\\nbad token!'; exit 0; }
    printf '2027-02-20T10:00:00Z\\n$token'; exit 0 ;;
  *"create token"*) printf '$token\\n'; exit 0 ;;
  *"cluster.server"*)
    [ "$mode" = http ] && { printf 'http://10.0.0.1:6443'; exit 0; }
    printf 'https://127.0.0.1:6443'; exit 0 ;;
  *"certificate-authority-data"*)
    [ "$mode" = noca ] && exit 0
    printf 'Q0EtREFUQQ=='; exit 0 ;;
  *"delete "*) exit 0 ;;
esac
exit 3
''');
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('k8s_reader');
      home = Directory('${dir.path}/home')..createSync();
      addTearDown(() {
        Process.runSync('chmod', ['-R', 'u+w', dir.path]);
        dir.deleteSync(recursive: true);
      });
      // sudo -S -p '': the password is the first stdin line.
      script('sudo', '''
[ "\$1" = -S ] && shift
[ "\$1" = -p ] && shift 2
IFS= read -r pw
[ "\$pw" = "$pass" ] || { echo "sudo: incorrect password" >&2; exit 1; }
printf 'sudo %s\\n' "\$*" >> "${log().path}"
exec "\$@"
''');
      script('stat', 'echo 0');
      // Only the kubeadm admin file "exists" for root.
      script('test', '''
[ "\$1" = -f ] && [ "\$2" = /etc/kubernetes/admin.conf ] && exit 0
[ "\$1" = -f ] && case "\$2" in /etc/*) exit 1 ;; esac
exec /usr/bin/test "\$@"
''');
    });

    Future<ProcessResult> run(String sh, {String stdin = '$pass\n'}) async {
      final p = await Process.start(
        'sh',
        ['-c', sh],
        environment: {
          'PATH': '${dir.path}/bin:${Platform.environment['PATH']}',
          'HOME': home.path,
        },
      );
      p.stdin.write(stdin);
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      final err = await p.stderr.transform(utf8.decoder).join();
      return ProcessResult(p.pid, await p.exitCode, out, err);
    }

    String calls() => log().existsSync() ? log().readAsStringSync() : '';

    test('writes a 0600 kubeconfig; token and password stay out of output '
        'and argv', () async {
      fakeKubectl();
      final r = await run(buildK8sReaderSetupScript(KubectlFlavor.kubectl));
      final result = parseK8sReaderOutput(r.stdout as String);
      expect(
        result.outcome,
        K8sReaderOutcome.ok,
        reason: '${r.stdout}${r.stderr}',
      );
      expect(result.via, '/etc/kubernetes/admin.conf');
      expect(result.expires, DateTime.utc(2027, 2, 20, 10));

      final cfg = File('${home.path}/.kube/kelola.yaml');
      final mode = Process.runSync('/usr/bin/stat', ['-c', '%a', cfg.path]);
      expect((mode.stdout as String).trim(), '600');
      final body = cfg.readAsStringSync();
      expect(body, contains('    token: $token\n'));
      expect(body, contains('    server: "https://127.0.0.1:6443"\n'));
      expect(body, contains('    certificate-authority-data: Q0EtREFUQQ==\n'));
      expect(body, contains('# kelola-expires: 2027-02-20T10:00:00Z\n'));
      expect(body, contains('current-context: kelola-reader'));
      // No temp file left behind.
      expect(Directory('${home.path}/.kube').listSync().map((e) => e.path), [
        cfg.path,
      ]);

      for (final out in [r.stdout as String, r.stderr as String, calls()]) {
        expect(out, isNot(contains(token)));
        expect(out, isNot(contains(pass)));
      }
      // Root ran the admin kubeconfig, the login ran the reader checks.
      expect(
        calls(),
        contains(
          'sudo ${dir.path}/bin/kubectl '
          '--kubeconfig=/etc/kubernetes/admin.conf',
        ),
      );
      expect(
        calls(),
        contains(
          'kubectl --kubeconfig=${home.path}/.kube/kelola.yaml auth can-i list pods',
        ),
      );
      expect(
        File('${dir.path}/applied.yaml').readAsStringSync(),
        kelolaReaderManifest(),
      );
      // The admin kubeconfig is never copied to the login.
      expect(body, isNot(contains('admin')));

      // The status read sees it without printing the token.
      final s = await run(k8sReaderStatusCommand, stdin: '');
      expect(s.stdout, isNot(contains(token)));
      final status = parseK8sReaderStatus(s.stdout as String);
      expect(status.present, isTrue);
      expect(status.expires, DateTime.utc(2027, 2, 20, 10));
    });

    test('k3s runs `k3s kubectl` with the k3s admin file', () async {
      fakeKubectl();
      script('k3s', '[ "\$1" = kubectl ] && shift; exec kubectl "\$@"');
      script('test', '''
[ "\$1" = -f ] && [ "\$2" = /etc/rancher/k3s/k3s.yaml ] && exit 0
exec /usr/bin/test "\$@"
''');
      final r = await run(buildK8sReaderSetupScript(KubectlFlavor.k3s));
      expect(
        parseK8sReaderOutput(r.stdout as String).via,
        '/etc/rancher/k3s/k3s.yaml',
      );
      expect(
        calls(),
        contains(
          'sudo ${dir.path}/bin/k3s kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml',
        ),
      );
    });

    test(
      'without -o on create token, the token still lands; no expiry',
      () async {
        fakeKubectl(mode: 'nojsonpath');
        final r = await run(buildK8sReaderSetupScript(KubectlFlavor.kubectl));
        final result = parseK8sReaderOutput(r.stdout as String);
        expect(result.outcome, K8sReaderOutcome.ok);
        expect(result.expires, isNull);
        expect(
          File('${home.path}/.kube/kelola.yaml').readAsStringSync(),
          contains('    token: $token\n'),
        );
      },
    );

    for (final (mode, want) in [
      ('unreachable', K8sReaderOutcome.unreachable),
      ('conflict', K8sReaderOutcome.conflict),
      ('noca', K8sReaderOutcome.noCa),
      ('badtoken', K8sReaderOutcome.failed),
      ('http', K8sReaderOutcome.failed),
    ]) {
      test('$mode: nothing is written', () async {
        fakeKubectl(mode: mode);
        final r = await run(buildK8sReaderSetupScript(KubectlFlavor.kubectl));
        expect(parseK8sReaderOutput(r.stdout as String).outcome, want);
        expect(File('${home.path}/.kube/kelola.yaml').existsSync(), isFalse);
        expect(r.stdout, isNot(contains(token)));
      });
    }

    test('a wrong password and no own access: noadmin', () async {
      fakeKubectl();
      final r = await run(
        buildK8sReaderSetupScript(KubectlFlavor.kubectl),
        stdin: 'wrong\n',
      );
      expect(
        parseK8sReaderOutput(r.stdout as String).outcome,
        K8sReaderOutcome.noAdmin,
      );
    });

    test(
      'a wrong password but an admin kubeconfig of the login: own',
      () async {
        fakeKubectl(canI: 'yes');
        final r = await run(
          buildK8sReaderSetupScript(KubectlFlavor.kubectl),
          stdin: 'wrong\n',
        );
        final result = parseK8sReaderOutput(r.stdout as String);
        expect(result.outcome, K8sReaderOutcome.ok);
        expect(result.via, 'own');
        expect(calls(), isNot(contains('sudo ${dir.path}/bin/kubectl')));
      },
    );

    test('a login-writable CLI is never run as root', () async {
      fakeKubectl();
      Process.runSync('chmod', ['755', '${dir.path}/bin/kubectl']);
      final r = await run(buildK8sReaderSetupScript(KubectlFlavor.kubectl));
      expect(
        parseK8sReaderOutput(r.stdout as String).outcome,
        K8sReaderOutcome.noCli,
      );
      expect(calls(), isNot(contains('sudo')));
    });

    test('remove deletes by label and the kubeconfig', () async {
      fakeKubectl();
      Directory('${home.path}/.kube').createSync();
      File('${home.path}/.kube/kelola.yaml').writeAsStringSync('x');
      final r = await run(buildK8sReaderRemoveScript(KubectlFlavor.kubectl));
      expect(
        parseK8sReaderOutput(r.stdout as String).outcome,
        K8sReaderOutcome.removed,
      );
      expect(File('${home.path}/.kube/kelola.yaml').existsSync(), isFalse);
      expect(
        calls(),
        contains(
          'delete clusterrolebinding,clusterrole,namespace '
          '--selector=app.kubernetes.io/name=kelola-reader,'
          'app.kubernetes.io/managed-by=kelola',
        ),
      );
    });
  });
}
