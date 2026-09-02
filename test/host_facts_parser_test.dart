import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/facts/host_facts_parser.dart';

String fixture(String name) =>
    File('test/fixtures/host_facts/$name').readAsStringSync();

void main() {
  const parser = HostFactsParser();

  test('Ubuntu 24.04', () {
    final facts = parser.parse(fixture('ubuntu_24.04.txt'));
    expect(facts.osId, 'ubuntu');
    expect(facts.osVersionId, '24.04');
    expect(facts.init, InitSystem.systemd);
    expect(facts.systemdVersion, 255);
    expect(facts.pkg, PackageManager.apt);
    expect(facts.fw, FirewallBackend.ufw);
    expect(facts.journalReadable, isTrue);
    expect(facts.arch, 'x86_64');
    expect(facts.nprocCores, 4);
  });

  test('Debian 12 without systemd-journal group', () {
    final facts = parser.parse(fixture('debian_12.txt'));
    expect(facts.osId, 'debian');
    expect(facts.init, InitSystem.systemd);
    expect(facts.systemdVersion, 252);
    expect(facts.journalReadable, isFalse);
    expect(facts.pkg, PackageManager.apt);
  });

  test('Rocky 9 prefers dnf and firewalld', () {
    final facts = parser.parse(fixture('rocky_9.txt'));
    expect(facts.osId, 'rocky');
    expect(facts.pkg, PackageManager.dnf);
    expect(facts.fw, FirewallBackend.firewalld);
    expect(facts.journalReadable, isTrue);
  });

  test('Alpine uses OpenRC and apk, does not claim systemd', () {
    final facts = parser.parse(fixture('alpine_3.20.txt'));
    expect(facts.osId, 'alpine');
    expect(facts.init, InitSystem.openrc);
    expect(facts.systemdVersion, isNull);
    expect(facts.pkg, PackageManager.apk);
    expect(facts.hasJournald, isFalse);
    expect(facts.arch, 'aarch64');
    expect(facts.nprocCores, isNull);
  });

  test('nproc stdout 1 is one core', () {
    expect(HostFactsParser.parseNproc('1\n'), 1);
    expect(HostFactsParser.parseNproc('1'), 1);
  });

  test('missing empty or garbage nproc is unknown, never 1', () {
    expect(HostFactsParser.parseNproc(''), isNull);
    expect(HostFactsParser.parseNproc('   '), isNull);
    expect(HostFactsParser.parseNproc('0'), isNull);
    expect(HostFactsParser.parseNproc('nproc: command not found'), isNull);
    expect(HostFactsParser.parseNproc('1 extra'), isNull);
    expect(HostFactsParser.parseNproc('foo'), isNull);
    final missing = parser.parse(
      '---OS---\nID=alpine\n---ARCH---\nx86_64\n',
    );
    expect(missing.nprocCores, isNull);
    final emptySection = parser.parse(
      '---OS---\nID=debian\n---NPROC---\n\n---ARCH---\nx86_64\n',
    );
    expect(emptySection.nprocCores, isNull);
    final garbage = parser.parse(
      '---OS---\nID=debian\n---NPROC---\n1 extra\n---ARCH---\nx86_64\n',
    );
    expect(garbage.nprocCores, isNull);
  });

  test('vendor and product become Model', () {
    final facts = parser.parse('''
---OS---
ID=debian
---DMI---
sys_vendor=Dell Inc.
product_name=PowerEdge R640
---SERIAL---
REQUIRES_ROOT
''');
    expect(facts.model, 'Dell Inc. PowerEdge R640');
  });

  test('missing sysfs keys omit Model', () {
    final facts = parser.parse('''
---OS---
ID=debian
---DMI---
---ARCH---
x86_64
''');
    expect(facts.model, isNull);
  });

  test('unreadable DMI fields omit Model rather than unknown', () {
    final facts = parser.parse(fixture('ubuntu_24.04.txt'));
    expect(facts.model, isNull);
    expect(facts.serialStatus, SerialStatus.missing);
    expect(facts.nics, isEmpty);
    expect(facts.gpu, isNull);
  });

  test('serial sudo fail is requiresRoot, not a blank serial', () {
    final facts = parser.parse('''
---OS---
ID=debian
---SERIAL---
REQUIRES_ROOT
''');
    expect(facts.serial, isNull);
    expect(facts.serialStatus, SerialStatus.requiresRoot);
  });

  test('passwordless dmidecode fills serial', () {
    final facts = parser.parse('''
---OS---
ID=debian
---SERIAL---
OK
ABC1237F2K
''');
    expect(facts.serial, 'ABC1237F2K');
    expect(facts.serialStatus, SerialStatus.available);
  });

  test('loopback is skipped; eth0 IPv4 IPv6 and MAC are kept', () {
    final facts = parser.parse('''
---OS---
ID=debian
---ADDR---
[{"ifname":"lo","flags":["LOOPBACK","UP"],"address":"00:00:00:00:00:00","addr_info":[{"family":"inet","local":"127.0.0.1","prefixlen":8},{"family":"inet6","local":"::1","prefixlen":128}]},{"ifname":"eth0","flags":["BROADCAST","UP","LOWER_UP"],"address":"aa:bb:cc:dd:ee:ff","addr_info":[{"family":"inet","local":"192.168.1.24","prefixlen":24,"scope":"global"},{"family":"inet6","local":"fe80::1","prefixlen":64,"scope":"link"},{"family":"inet6","local":"2001:db8::24","prefixlen":64,"scope":"global"}]}]
''');
    expect(facts.nics, hasLength(1));
    expect(facts.nics.single.name, 'eth0');
    expect(facts.nics.single.mac, 'aa:bb:cc:dd:ee:ff');
    expect(facts.nics.single.ipv4, '192.168.1.24');
    expect(facts.nics.single.ipv6, '2001:db8::24');
  });

  test('no GPU section leaves gpu absent', () {
    final facts = parser.parse('''
---OS---
ID=debian
---GPU---
---NVIDIA---
''');
    expect(facts.gpu, isNull);
  });

  test('nvidia-smi fills name VRAM and driver', () {
    final facts = parser.parse('''
---OS---
ID=debian
---GPU---
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA102 [GeForce RTX 3080] [10de:2206] (rev a1)
---NVIDIA---
NVIDIA GeForce RTX 3080, 10240 MiB, 550.54.14
''');
    expect(facts.gpu, isNotNull);
    expect(facts.gpu!.model, 'NVIDIA GeForce RTX 3080');
    expect(facts.gpu!.vram, '10240 MiB');
    expect(facts.gpu!.driver, '550.54.14');
  });

  test('lspci VGA without nvidia-smi still counts as a GPU', () {
    final facts = parser.parse('''
---OS---
ID=debian
---GPU---
00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics 630 [8086:3e92]
---NVIDIA---
''');
    expect(facts.gpu?.model, contains('UHD Graphics 630'));
    expect(facts.gpu?.vram, isNull);
    expect(facts.gpu?.driver, isNull);
  });

  test('virt Q35 product_name is shown as-is', () {
    final facts = parser.parse('''
---OS---
ID=debian
---DMI---
sys_vendor=QEMU
product_name=Standard PC (Q35 + ICH9, 2009)
---VIRT---
kvm
''');
    expect(facts.model, 'QEMU Standard PC (Q35 + ICH9, 2009)');
    expect(facts.virt, 'kvm');
  });

  test('VMware Virtual Platform product is shown as-is', () {
    final facts = parser.parse('''
---OS---
ID=debian
---DMI---
sys_vendor=VMware, Inc.
product_name=VMware Virtual Platform
---VIRT---
vmware
''');
    expect(facts.model, 'VMware, Inc. VMware Virtual Platform');
  });

  test('firmware fields parse from DMI sysfs', () {
    final facts = parser.parse('''
---OS---
ID=debian
---DMI---
sys_vendor=Dell Inc.
product_name=PowerEdge R640
bios_vendor=Dell Inc.
bios_version=2.10.2
bios_date=11/12/2021
''');
    expect(facts.biosVendor, 'Dell Inc.');
    expect(facts.biosVersion, '2.10.2');
    expect(facts.biosDate, '11/12/2021');
  });
}

