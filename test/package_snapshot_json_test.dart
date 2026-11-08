import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';

void main() {
  test('PackageSnapshot JSON round-trips fields', () {
    const snap = PackageSnapshot(
      manager: PackageManager.dnf,
      updates: [
        PackageUpdate(
          name: 'openssl',
          currentVersion: '1',
          candidateVersion: '2',
          security: true,
        ),
        PackageUpdate(name: 'curl'),
      ],
      rebootRequired: true,
      rebootReasons: ['/var/run/reboot-required'],
    );
    final decoded = PackageSnapshot.fromJson(
      jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.manager, PackageManager.dnf);
    expect(decoded.rebootRequired, isTrue);
    expect(decoded.rebootReasons, ['/var/run/reboot-required']);
    expect(decoded.updates, hasLength(2));
    expect(decoded.updates.first.name, 'openssl');
    expect(decoded.updates.first.security, isTrue);
    expect(decoded.updates.first.currentVersion, '1');
    expect(decoded.updates.first.candidateVersion, '2');
    expect(decoded.updates[1].name, 'curl');
    expect(decoded.updates[1].security, isFalse);
  });

  test('unknown manager name falls back to PackageManager.unknown', () {
    final decoded = PackageSnapshot.fromJson({
      'manager': 'not-a-real-mgr',
      'updates': <Object>[],
      'rebootRequired': false,
      'rebootReasons': <Object>[],
    });
    expect(decoded.manager, PackageManager.unknown);
  });
}
