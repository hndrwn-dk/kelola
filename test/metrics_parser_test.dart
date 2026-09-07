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

  test('excludes the probe ps process from top lists', () {
    const raw = '''
---STAT1---
cpu  10 0 10 80 0 0 0
---LOAD---
0.01 0.01 0.01 1/120 99
---MEM---
MemTotal:        1000 kB
MemAvailable:     700 kB
---TOPCPU---
 4608 hendr 300.0  0.1  4096 ps
 2127 root    0.4  0.0  1024 kworker/0:2-events
---TOPMEM---
 1200 root    0.1  5.7 8192 dockerd
 4609 hendr   0.0  0.1  4096 ps
---STAT2---
cpu  20 0 20 90 0 0 0
''';
    final snap = const MetricsParser().parse(raw);
    expect(snap.topCpu.map((p) => p.command), ['kworker/0:2-events']);
    expect(snap.topMem.map((p) => p.command), ['dockerd']);
  });
}
