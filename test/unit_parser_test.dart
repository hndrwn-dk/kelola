import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/units/unit_detail_parser.dart';
import 'package:kelola/domain/units/unit_list_parser.dart';

String _fixture(String name) =>
    File('test/fixtures/units/$name').readAsStringSync();

void main() {
  test('parses systemd JSON list and merges unit-file state', () {
    final result = const UnitListParser().parse(
      stdout: _fixture('list_json.txt'),
      initSupported: true,
    );
    expect(result.initSupported, isTrue);
    expect(result.units.first.isFailed, isTrue);
    expect(result.units.first.name, 'nginx.service');
    expect(result.units.first.unitFileState, 'enabled');
    expect(result.failed, hasLength(1));
    final ssh = result.units.firstWhere((u) => u.name == 'ssh.service');
    expect(ssh.isActive, isTrue);
  });

  test('falls back to plain columns when JSON is unusable', () {
    final result = const UnitListParser().parse(
      stdout: _fixture('list_plain.txt'),
      initSupported: true,
    );
    expect(result.units.map((u) => u.name), contains('broken.service'));
    final broken =
        result.units.firstWhere((u) => u.name == 'broken.service');
    expect(broken.isFailed, isTrue);
    expect(broken.unitFileState, 'disabled');
  });

  test('parses OpenRC rc-status', () {
    final result = const UnitListParser().parse(
      stdout: _fixture('openrc.txt'),
      initSupported: true,
    );
    expect(result.failed.single.name, 'nginx');
    expect(
      result.units.firstWhere((u) => u.name == 'sshd').isActive,
      isTrue,
    );
  });

  test('parses systemctl show properties and logs', () {
    final detail = const UnitDetailParser().parse(
      _fixture('show.txt'),
      'nginx.service',
    );
    expect(detail.activeState, 'failed');
    expect(detail.fragmentPath, contains('nginx.service'));
    expect(detail.logs, contains('Address already in use'));
  });
}
