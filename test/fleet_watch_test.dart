import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/fleet/fleet_watch.dart';

FleetHostHealth _h({
  bool reachable = true,
  int disk = 10,
  int mem = 40,
  int failed = 0,
  int containersDown = 0,
  bool reboot = false,
}) {
  return FleetHostHealth(
    hostId: 'h1',
    alias: 'web',
    reachable: reachable,
    load1: 0.2,
    nprocCores: 4,
    memPercent: mem,
    diskRootPercent: disk,
    failedUnitCount: failed,
    pendingUpdates: 4,
    securityUpdates: 2,
    containersDown: containersDown,
    containersUnhealthy: 0,
    rebootRequired: reboot,
    fetchedAt: DateTime.utc(2026, 9, 27),
  );
}

void main() {
  test('watch assessment uses user thresholds and drops non-watch signals', () {
    final tight = assessFleetHost(
      _h(disk: 82, mem: 81, failed: 1),
      thresholds: const FleetWatchThresholds(diskPercent: 80, memPercent: 80),
    );
    final watch = fleetWatchAssessment(
      _h(disk: 82, mem: 81, failed: 1),
      const FleetWatchThresholds(diskPercent: 80, memPercent: 80),
    );
    expect(tight.issues.any((i) => i.kind == FleetIssueKind.diskCritical), isTrue);
    expect(
      tight.issues
          .firstWhere((i) => i.kind == FleetIssueKind.diskCritical)
          .meta,
      contains('/:82%'),
    );
    expect(watch.issues.any((i) => i.kind == FleetIssueKind.pendingUpdates), isFalse);
    expect(watch.issues.any((i) => i.kind == FleetIssueKind.securityUpdates), isFalse);
    expect(
      watch.issues.map((i) => i.kind),
      containsAll([FleetIssueKind.diskCritical, FleetIssueKind.failedUnit]),
    );
  });

  test('default thresholds match the live fleet tile rules for watch signals', () {
    expect(
      fleetWatchAssessment(_h(disk: 90), FleetWatchThresholds.defaults)
          .issues
          .map((i) => i.kind),
      contains(FleetIssueKind.diskCritical),
    );
    expect(
      fleetWatchAssessment(_h(disk: 89), FleetWatchThresholds.defaults).issues,
      isEmpty,
    );
  });

  test('fingerprint changes only notify after a stored baseline', () {
    final unhealthy = fleetWatchFingerprint(
      fleetWatchAssessment(_h(failed: 2), FleetWatchThresholds.defaults),
    );
    final healthy = fleetWatchFingerprint(
      fleetWatchAssessment(_h(), FleetWatchThresholds.defaults),
    );
    expect(fleetWatchShouldNotify(previous: null, current: unhealthy), isFalse);
    expect(fleetWatchShouldNotify(previous: healthy, current: unhealthy), isTrue);
    expect(fleetWatchShouldNotify(previous: unhealthy, current: unhealthy), isFalse);
    expect(fleetWatchShouldNotify(previous: unhealthy, current: healthy), isTrue);
  });

  test('scheduler floor is hourly, never a 15-minute promise', () {
    expect(kFleetWatchMinInterval, const Duration(hours: 1));
    expect(kFleetWatchMinInterval.inMinutes, greaterThanOrEqualTo(60));
    final now = DateTime.utc(2026, 9, 27, 12);
    expect(fleetWatchIsDue(lastTickUtc: null, now: now), isTrue);
    expect(
      fleetWatchIsDue(
        lastTickUtc: now.subtract(const Duration(minutes: 59)),
        now: now,
      ),
      isFalse,
    );
    expect(
      fleetWatchIsDue(
        lastTickUtc: now.subtract(const Duration(hours: 1)),
        now: now,
      ),
      isTrue,
    );
  });

  test('WorkManager is new enough for AGP 9 R8 full mode', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final rules = File('android/app/proguard-rules.pro');
    expect(
      gradle,
      isNot(contains('work-runtime-ktx:2.9.')),
      reason: '2.9.x dies at launch under R8 full mode (WorkDatabase.canonicalName)',
    );
    expect(gradle, contains('work-runtime-ktx:2.1'));
    expect(rules.existsSync(), isTrue);
    final keep = rules.readAsStringSync();
    expect(keep, contains('androidx.work'));
    expect(keep, contains('<init>'));
  });

  test('fleet watch uses its own notification channel, not tunnel FGS', () {
    final plugin = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/FleetWatchPlugin.kt',
    ).readAsStringSync();
    expect(plugin, contains('kelola_fleet'));
    expect(plugin, contains('PeriodicWorkRequestBuilder'));
    expect(plugin, isNot(contains('kelola_tunnels')));
    expect(plugin, isNot(contains('startForegroundService')));
    final domain = File('lib/domain/fleet/fleet_watch.dart').readAsStringSync();
    expect(domain, isNot(contains('entitlement')));
  });
}
