import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';

void main() {
  test('dashboard sparkline series is normalized 0..1 from CPU percents', () {
    expect(normalizeSparkPercents([0, 50, 100]), [0.0, 0.5, 1.0]);
    expect(normalizeSparkPercents([150, -10]), [1.0, 0.0]);
  });

  test('load meter uses nproc cores as denominator', () {
    expect(loadMeterFraction(0.84, 4), closeTo(0.21, 0.001));
    expect(loadMeterFraction(8, 8), 1.0);
    expect(loadMeterFraction(1, null), isNull);
    expect(loadMeterFraction(1, 0), isNull);
  });
}
