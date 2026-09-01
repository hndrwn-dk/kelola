import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
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
  });
}
