import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/metrics/rate_sample.dart';

void main() {
  test('rate sample interval is one shared duration', () {
    expect(kRateSampleInterval, const Duration(seconds: 1));
  });

  test('diskstats rates from two samples', () {
    const a = '''
   8       0 sda 100 0 2000 10 50 0 1000 20 0 100 0
   8       1 sda1 10 0 100 1 5 0 50 2 0 10 0
 259       0 nvme0n1 200 0 4000 20 100 0 2000 40 0 200 0
''';
    const b = '''
   8       0 sda 200 0 4000 10 150 0 3000 20 0 600 0
   8       1 sda1 20 0 200 1 10 0 100 2 0 20 0
 259       0 nvme0n1 300 0 6000 20 200 0 4000 40 0 700 0
''';
    final rates = DiskIoRates.between(
      DiskIoCounters.parse(a),
      DiskIoCounters.parse(b),
      const Duration(seconds: 1),
    );
    expect(rates.map((r) => r.name), ['nvme0n1', 'sda']);
    final sda = rates.firstWhere((r) => r.name == 'sda');
    // sectors * 512 / s = (2000)*512 = 1_024_000 B/s read
    expect(sda.readBytesPerSec, 1024000);
    expect(sda.writeBytesPerSec, 1024000);
    expect(sda.readIops, 100);
    expect(sda.writeIops, 100);
    expect(sda.busyPercent, 50); // 500ms io_ticks / 1000ms
  });

  test('netdev rates from two samples', () {
    const a = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 1000 10 0 0 0 0 0 0 1000 10 0 0 0 0 0 0
  eth0: 2000 20 1 0 0 0 0 0 4000 40 2 0 0 0 0 0
''';
    const b = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 2000 20 0 0 0 0 0 0 2000 20 0 0 0 0 0 0
  eth0: 4000 40 1 0 0 0 0 0 8000 80 2 0 0 0 0 0 0
''';
    final rates = NetDevRates.between(
      NetDevCounters.parse(a),
      NetDevCounters.parse(b),
      const Duration(seconds: 1),
    );
    expect(rates.map((r) => r.name), ['eth0']);
    final eth = rates.single;
    expect(eth.rxBytesPerSec, 2000);
    expect(eth.txBytesPerSec, 4000);
    expect(eth.rxPacketsPerSec, 20);
    expect(eth.txPacketsPerSec, 40);
    expect(eth.rxErrors, 1);
    expect(eth.txErrors, 2);
  });

  test('CpuStatBreakdown splits user system iowait from /proc/stat delta', () {
    final a = CpuStatCounters.parse('cpu  100 0 50 200 10 0 0');
    final b = CpuStatCounters.parse('cpu  110 0 55 270 25 0 0');
    final cpu = CpuStatBreakdown.between(a, b);
    expect(cpu.userPercent, closeTo(10, 0.01));
    expect(cpu.systemPercent, closeTo(5, 0.01));
    expect(cpu.iowaitPercent, closeTo(15, 0.01));
    expect(cpu.busyPercent, closeTo(30, 0.01));
  });
}
