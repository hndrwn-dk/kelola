import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/probes/metrics_probe.dart';

void main() {
  test('cpu percent from successive /proc/stat samples', () {
    const raw = '''
---STAT1---
cpu  10 0 10 80 0 0 0
---LOAD---
0.42 0.40 0.39 1/120 99
---MEM---
MemTotal:        1000 kB
MemAvailable:     250 kB
---TOPCPU---
  420 hendr  12.0  1.5  8192 nginx
---TOPMEM---
  421 root    0.1  8.0 32768 k3s
---STAT2---
cpu  20 0 20 90 0 0 0
''';
    final snap = const MetricsParser().parse(raw);
    expect(snap.cpuPercent, closeTo(66.6, 1));
    expect(snap.load1, 0.42);
    expect(snap.memUsedPercent, 75);
    expect(snap.topCpu.single.command, 'nginx');
    expect(snap.topMem.single.command, 'k3s');
  });
}
