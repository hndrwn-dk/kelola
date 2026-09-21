import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/app_lock/app_lock_timeout.dart';

void main() {
  test('fromSeconds maps stored values and fails open on junk', () {
    expect(AppLockTimeout.fromSeconds(0), AppLockTimeout.off);
    expect(AppLockTimeout.fromSeconds(-1), AppLockTimeout.immediately);
    expect(AppLockTimeout.fromSeconds(60), AppLockTimeout.oneMinute);
    expect(AppLockTimeout.fromSeconds(300), AppLockTimeout.fiveMinutes);
    expect(AppLockTimeout.fromSeconds(900), AppLockTimeout.fifteenMinutes);
    expect(AppLockTimeout.fromSeconds(12), AppLockTimeout.off);
  });

  test('labels are human copy', () {
    expect(AppLockTimeout.off.label, 'Off');
    expect(AppLockTimeout.immediately.label, 'Immediately');
    expect(AppLockTimeout.oneMinute.label, '1 minute');
    expect(AppLockTimeout.fiveMinutes.label, '5 minutes');
    expect(AppLockTimeout.fifteenMinutes.label, '15 minutes');
  });

  test('shouldLockOnResume respects off, immediately, and elapsed window', () {
    final paused = DateTime.utc(2026, 9, 21, 12);
    expect(
      shouldLockOnResume(timeoutSec: 0, pausedAt: paused, now: paused),
      isFalse,
    );
    expect(
      shouldLockOnResume(timeoutSec: -1, pausedAt: paused, now: paused),
      isTrue,
    );
    expect(
      shouldLockOnResume(
        timeoutSec: 60,
        pausedAt: paused,
        now: paused.add(const Duration(seconds: 59)),
      ),
      isFalse,
    );
    expect(
      shouldLockOnResume(
        timeoutSec: 60,
        pausedAt: paused,
        now: paused.add(const Duration(seconds: 60)),
      ),
      isTrue,
    );
    expect(
      shouldLockOnResume(timeoutSec: 60, pausedAt: null, now: paused),
      isFalse,
    );
  });

  test('cold start and FLAG_SECURE follow timeout != off', () {
    expect(lockOnColdStart(0), isFalse);
    expect(lockOnColdStart(-1), isTrue);
    expect(recentsSecure(0), isFalse);
    expect(recentsSecure(60), isTrue);
  });
}
