import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _android = 'android/app/src/main/kotlin/com/tursinalabs/kelola';

void main() {
  test('startup cancels the job and channel left by fleet watch', () {
    final cleanup = File(
      '$_android/LegacyFleetWatchCleanup.kt',
    ).readAsStringSync();
    expect(cleanup, contains('"kelola_fleet_watch"'));
    expect(cleanup, contains('"kelola_fleet"'));
    expect(cleanup, contains('cancelUniqueWork(WORK_NAME)'));
    expect(cleanup, contains('deleteNotificationChannel(NOTIFY_CHANNEL)'));

    expect(
      File('$_android/MainActivity.kt').readAsStringSync(),
      contains('LegacyFleetWatchCleanup.run('),
    );
  });

  test('the cleanup cannot stop the app from starting', () {
    final cleanup = File(
      '$_android/LegacyFleetWatchCleanup.kt',
    ).readAsStringSync();
    expect(RegExp('runCatching').allMatches(cleanup).length, 2);
  });
}
