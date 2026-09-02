import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/screens/host_details_screen.dart';

void main() {
  testWidgets('host details lists full HostFacts off the dashboard',
      (tester) async {
    const host = Host(
      id: 'h1',
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
      keyAlias: 'kelola-user',
    );
    const facts = HostFacts(
      osId: 'debian',
      osVersionId: '12',
      prettyName: 'Debian 12',
      init: InitSystem.systemd,
      systemdVersion: 252,
      pkg: PackageManager.apt,
      fw: FirewallBackend.ufw,
      hasJournald: true,
      journalReadable: true,
      arch: 'x86_64',
      runtimes: ['docker'],
      nprocCores: 4,
    );

    await tester.pumpWidget(
      const KelolaApp(
        home: HostDetailsScreen(host: host, facts: facts),
      ),
    );

    expect(find.text('Host details'), findsOneWidget);
    expect(find.textContaining('systemd'), findsWidgets);
    expect(find.textContaining('apt'), findsWidgets);
    expect(find.textContaining('ufw'), findsWidgets);
    expect(find.textContaining('x86_64'), findsOneWidget);
    expect(find.textContaining('docker'), findsOneWidget);
    expect(find.textContaining('Debian 12'), findsOneWidget);
  });
}
