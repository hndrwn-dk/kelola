import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/facts/serial_mask.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/screens/host_details_screen.dart';

void main() {
  const host = Host(
    id: 'h1',
    alias: 'nas-01',
    address: '192.168.1.24',
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    lastSeenAt: null,
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

  testWidgets('host details uses hero plus grouped facts, not ten equal cards',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var edited = false;
    await tester.pumpWidget(
      KelolaApp(
        home: HostDetailsScreen(
          host: host,
          facts: facts,
          pinnedKey: const PinnedHostKey(
            algorithm: 'ssh-ed25519',
            fingerprint: 'SHA256:abc',
          ),
          connected: true,
          onEdit: () => edited = true,
        ),
      ),
    );

    expect(find.text('Host details'), findsOneWidget);
    expect(find.byType(HostHeroCard), findsOneWidget);
    expect(find.byType(FactGroup), findsNWidgets(3));
    expect(find.text('SYSTEM'), findsOneWidget);
    expect(find.text('TOOLING'), findsOneWidget);
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('Edit host'), findsOneWidget);
    expect(find.byType(ServiceRow), findsNothing);

    expect(find.text('nas-01'), findsWidgets);
    expect(find.text('192.168.1.24'), findsWidgets);
    expect(find.textContaining('Debian 12'), findsWidgets);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('systemd'), findsWidgets);
    expect(find.textContaining('apt'), findsWidgets);
    expect(find.textContaining('ufw'), findsWidgets);
    expect(find.textContaining('x86_64'), findsOneWidget);
    expect(find.textContaining('docker'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('ssh-ed25519'), findsOneWidget);
    expect(find.text('SHA256:abc'), findsOneWidget);

    await tester.tap(find.text('Edit host'));
    await tester.pump();
    expect(edited, isTrue);
  });

  testWidgets('missing nproc shows unknown, never 1', (tester) async {
    await tester.pumpWidget(
      const KelolaApp(
        home: HostDetailsScreen(
          host: host,
          facts: HostFacts(
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
          ),
        ),
      ),
    );

    expect(find.text('unknown'), findsWidgets);
    expect(find.text('1'), findsNothing);
    expect(find.text('Cores'), findsOneWidget);
  });

  testWidgets('FIRMWARE and NETWORK show when present; GPU group stays hidden',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const KelolaApp(
        home: HostDetailsScreen(
          host: host,
          facts: HostFacts(
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
            nprocCores: 4,
            model: 'Dell Inc. PowerEdge R640',
            biosVendor: 'Dell Inc.',
            biosVersion: '2.10.2',
            biosDate: '11/12/2021',
            runtimes: ['docker'],
            nics: [
              HostNic(
                name: 'eth0',
                mac: 'aa:bb:cc:dd:ee:ff',
                ipv4: '192.168.1.24',
                ipv6: '2001:db8::24',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('FIRMWARE'), findsOneWidget);
    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('GPU'), findsNothing);
    expect(find.text('none'), findsNothing);
    expect(find.text('Dell Inc. PowerEdge R640'), findsOneWidget);
    expect(find.text('Dell Inc.'), findsOneWidget);
    expect(find.text('2.10.2'), findsOneWidget);
    expect(find.text('11/12/2021'), findsOneWidget);
    expect(find.text('eth0'), findsWidgets);
    expect(find.text('192.168.1.24'), findsWidgets);
    expect(find.text('2001:db8::24'), findsOneWidget);
    expect(find.text('aa:bb:cc:dd:ee:ff'), findsOneWidget);
  });

  testWidgets('nvidia GPU name VRAM and driver appear in GPU group',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const KelolaApp(
        home: HostDetailsScreen(
          host: host,
          facts: HostFacts(
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
            gpu: HostGpu(
              model: 'NVIDIA GeForce RTX 3080',
              vram: '10240 MiB',
              driver: '550.54.14',
            ),
          ),
        ),
      ),
    );

    expect(find.text('GPU'), findsOneWidget);
    expect(find.text('NVIDIA GeForce RTX 3080'), findsOneWidget);
    expect(find.text('10240 MiB'), findsOneWidget);
    expect(find.text('550.54.14'), findsOneWidget);
  });

  testWidgets('serial sudo fail shows requires root, not a blank value',
      (tester) async {
    await tester.pumpWidget(
      const KelolaApp(
        home: HostDetailsScreen(
          host: host,
          facts: HostFacts(
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
            serialStatus: SerialStatus.requiresRoot,
          ),
        ),
      ),
    );

    expect(find.text('Serial'), findsOneWidget);
    expect(find.text('requires root'), findsOneWidget);
    expect(find.text('···· '), findsNothing);
  });

  testWidgets('serial is masked until tap, then revealed copied and audited',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    var revealed = 0;
    await tester.pumpWidget(
      KelolaApp(
        home: HostDetailsScreen(
          host: host,
          facts: const HostFacts(
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
            serial: 'ABC1237F2K',
            serialStatus: SerialStatus.available,
          ),
          onRevealSerial: () async {
            revealed++;
          },
        ),
      ),
    );

    expect(find.text('···· 7F2K'), findsOneWidget);
    expect(find.text('ABC1237F2K'), findsNothing);

    await tester.tap(find.text('···· 7F2K'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ABC1237F2K'), findsOneWidget);
    expect(copied, 'ABC1237F2K');
    expect(revealed, 1);
    expect(find.text('Copied'), findsOneWidget);
    expect(revealedSerialAuditTitle, isNot(contains('LC_ALL')));
  });
}

