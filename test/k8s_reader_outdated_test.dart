import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/probes/k8s_reader_probes.dart';
import 'package:kelola/presentation/screens/host_details_screen.dart';
import 'package:kelola/presentation/widgets/k8s_reader_flow.dart';

// An old read-only role (no argoproj.io rule) counts as outdated.

const _host = Host(
  id: 'h1',
  alias: 'k8s01',
  address: '192.168.1.10',
  port: 22,
  username: 'hendra',
  keyAlias: 'kelola-user',
  lastSeenAt: null,
);

final _kubectlFacts = HostFacts.undiscovered.copyWith(
  runtimes: ['kubectl'],
);

const _present = 'KELOLA_K8S_READER_PRESENT';
const _role = 'KELOLA_K8S_READER_ROLE=';

void main() {
  group('status parsing', () {
    test('ROLE=no on a present reader is outdated', () {
      final s = parseK8sReaderStatus('$_present\n${_role}no\n');
      expect(s.present, isTrue);
      expect(s.roleCurrent, isFalse);
      expect(s.roleOutdated, isTrue);
    });

    test('ROLE=yes is current, and keeps the expiry', () {
      final s = parseK8sReaderStatus(
        '2027-02-20T10:00:00Z\n$_present\n${_role}yes\n',
      );
      expect(s.roleCurrent, isTrue);
      expect(s.roleOutdated, isFalse);
      expect(s.expires, DateTime.utc(2027, 2, 20, 10));
    });

    test('no ROLE line: unknown, never outdated', () {
      final s = parseK8sReaderStatus('$_present\n');
      expect(s.roleCurrent, isNull);
      expect(s.roleOutdated, isFalse);
      expect(parseK8sReaderStatus('$_present\n${_role}maybe\n').roleCurrent,
          isNull);
    });

    test('an absent kubeconfig is never outdated', () {
      final s = parseK8sReaderStatus('KELOLA_K8S_READER_ABSENT\n${_role}no\n');
      expect(s.present, isFalse);
      expect(s.roleOutdated, isFalse);
    });
  });

  group('status command', () {
    test('kubectl and k3s check the argoproj.io rule, never print a token',
        () {
      for (final facts in [
        _kubectlFacts,
        HostFacts.undiscovered.copyWith(runtimes: ['k3s']),
      ]) {
        final cmd = k8sReaderStatusCommandFor(facts);
        // The role's rules, not API discovery: a cluster without the Argo CD
        // CRD cannot resolve the resource, and `can-i list` would say no.
        expect(cmd, contains('auth can-i --list --request-timeout=5s'));
        expect(cmd, isNot(contains('can-i list applications')));
        expect(cmd, contains(r"grep -q '^applications\.argoproj\.io '"));
        // A no only from a real rule listing while the API answers.
        expect(cmd, contains("grep -q '^Resources '"));
        expect(cmd, contains('get --raw=/version --request-timeout=5s'));
        expect(cmd, contains('${k8sReaderRoleMarker}yes'));
        expect(cmd, contains('${k8sReaderRoleMarker}no'));
        expect(cmd, contains("sed -n 's/^# kelola-expires: //p'"));
        expect(cmd, isNot(contains('token')));
        expect(cmd, isNot(contains('create token')));
      }
    });

    test('oc and no CLI keep the plain status command', () {
      expect(
        k8sReaderStatusCommandFor(HostFacts.undiscovered),
        k8sReaderStatusCommand,
      );
      expect(
        const K8sReaderStatusProbe().command(HostFacts.undiscovered),
        'echo $k8sReaderAbsentMarker',
      );
    });

    test('the probe uses the flavor-aware command', () {
      expect(
        const K8sReaderStatusProbe().command(_kubectlFacts),
        k8sReaderStatusCommandFor(_kubectlFacts),
      );
    });
  });

  group('copy', () {
    final now = DateTime.utc(2026, 11, 22);

    test('the outdated copy', () {
      expect(
        kelolaReaderRoleOutdatedCopy,
        'The read-only kelola-reader role is outdated. '
        'Re-run Enable Kelola sudo.',
      );
    });

    test('status line shows it, but an expired token comes first', () {
      expect(
        k8sReaderStatusLine(
          K8sReaderStatus(
            present: true,
            expires: DateTime.utc(2027, 2, 20),
            roleCurrent: false,
          ),
          now,
        ),
        kelolaReaderRoleOutdatedCopy,
      );
      expect(
        k8sReaderStatusLine(
          const K8sReaderStatus(present: true, roleCurrent: false),
          now,
        ),
        kelolaReaderRoleOutdatedCopy,
      );
      expect(
        k8sReaderStatusLine(
          K8sReaderStatus(
            present: true,
            expires: DateTime.utc(2026, 11, 1),
            roleCurrent: false,
          ),
          now,
        ),
        contains('expired on 1 Nov 2026'),
      );
      expect(
        k8sReaderStatusLine(
          K8sReaderStatus(
            present: true,
            expires: DateTime.utc(2027, 2, 20),
            roleCurrent: true,
          ),
          now,
        ),
        contains('Token until 20 Feb 2027'),
      );
    });
  });

  testWidgets('the Read access block shows it, with Renew', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: K8sReaderAccessBlock(
            status: K8sReaderStatus(
              present: true,
              expires: DateTime.utc(2027, 2, 20),
              roleCurrent: false,
            ),
            now: DateTime.utc(2026, 11, 22),
            onSetUp: () {},
            onRemove: () {},
          ),
        ),
      ),
    );
    expect(find.text(kelolaReaderRoleOutdatedCopy), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
  });

  group('host details row', () {
    Widget details(Future<bool> Function()? check) => KelolaApp(
      home: HostDetailsScreen(
        host: _host,
        facts: _kubectlFacts,
        checkReaderRole: check,
      ),
    );

    testWidgets('shows when the check resolves true', (tester) async {
      await tester.pumpWidget(details(() async => true));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Kubernetes reader'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(kelolaReaderRoleOutdatedCopy), findsOneWidget);
    });

    testWidgets('hidden when false, when it throws, or without a check', (
      tester,
    ) async {
      for (final check in <Future<bool> Function()?>[
        () async => false,
        () => Future<bool>.error('offline'),
        null,
      ]) {
        await tester.pumpWidget(details(check));
        await tester.pumpAndSettle();
        expect(find.text('Kubernetes reader'), findsNothing);
      }
    });
  });
}
