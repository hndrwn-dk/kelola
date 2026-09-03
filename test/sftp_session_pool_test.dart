import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SFTP goes through execute with audit and no whole-file buffer', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, contains('SftpProbe'));
    expect(src, contains('client.sftp()'));
    expect(src, contains('isStream'));
    expect(src, contains('AuditDraft.fromProbe'));
    expect(src, isNot(contains('readAsBytes()')));
    expect(src, isNot(contains('readAsString()')));
  });

  test('adapter streams read and write and never concatenates the file', () {
    final adapter = File('lib/data/ssh/dart_sftp_port.dart').readAsStringSync();
    expect(adapter, contains('abort()'));
    expect(adapter, isNot(contains('readAsBytes()')));
    expect(adapter, isNot(contains('readBytes(')));
    final probe = File('lib/domain/probes/sftp_probe.dart').readAsStringSync();
    expect(probe, contains('openRead()'));
    expect(probe, contains('openWrite()'));
    expect(probe, isNot(contains('readAsBytes()')));
  });

  test('dashboard exposes Files as an sftp tool tile', () {
    final src = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(src, contains("label: 'Files'"));
    expect(src, contains('FilesScreen'));
  });
}
