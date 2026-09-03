import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/probes/container_logs_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('container logs probe keeps twenty lines', () {
    const probe = ContainerLogsProbe(
      ContainerRow(
        id: 'abc',
        names: 'web',
        image: 'nginx',
        state: 'restarting',
        status: 'Restarting (1)',
      ),
    );
    final stdout = List.generate(25, (i) => 'line $i').join('\n');
    expect(probe.parse(stdout, '', 0), hasLength(20));
    expect(probe.parse(stdout, '', 0).first, 'line 0');
    expect(probe.risk, RiskLevel.read);
  });
}
