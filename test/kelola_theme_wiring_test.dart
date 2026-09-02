import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';

void main() {
  test('forRisk accepts Probe.risk from the domain enum', () {
    const probe = HostActionProbe(HostVerb.reboot);
    expect(probe.risk, RiskLevel.destructive);
    expect(
      KelolaColors.dark.forRisk(probe.risk),
      KelolaColors.dark.red,
    );
  });

  testWidgets('KelolaApp registers design colors on context.kc', (tester) async {
    late KelolaColors kc;
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            kc = context.kc;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(kc.ink, const Color(0xFF0E1116));
    expect(kc.forRisk(RiskLevel.mutate), kc.amber);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.theme!.scaffoldBackgroundColor, const Color(0xFF0E1116));
    expect(app.darkTheme!.scaffoldBackgroundColor, const Color(0xFF0E1116));
  });

  test('forHealth maps status, not RiskLevel', () {
    const c = KelolaColors.dark;
    expect(c.forHealth(HealthStatus.healthy), c.green);
    expect(c.forHealth(HealthStatus.warning), c.amber);
    expect(c.forHealth(HealthStatus.failed), c.red);
    expect(c.forHealth(HealthStatus.unknown), c.dim);
    expect(c.forHealth(HealthStatus.healthy), isNot(c.forRisk(RiskLevel.read)));
  });
}
