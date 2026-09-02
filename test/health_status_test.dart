import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

Finder statusDotFinder() => find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
    });

Widget pumpRow(ServiceRow row) {
  return MaterialApp(
    theme: buildKelolaDarkTheme(),
    home: Scaffold(body: row),
  );
}

void main() {
  testWidgets('ServiceRow paints health on the dot and band; meta stays muted',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: const Scaffold(
          body: ServiceRow(
            risk: RiskLevel.mutate,
            status: HealthStatus.failed,
            name: 'nginx.service',
            meta: 'failed · exit 1 · 09:12',
            pillText: 'restart',
          ),
        ),
      ),
    );

    final band = tester.widget<RiskBand>(find.byType(RiskBand));
    expect(band.risk, RiskLevel.mutate);
    expect(band.status, HealthStatus.failed);

    final dot = tester.widget<Container>(statusDotFinder());
    expect((dot.decoration as BoxDecoration).color, KelolaColors.dark.red);

    final meta = tester.widget<Text>(find.text('failed · exit 1 · 09:12'));
    expect(meta.style?.color, KelolaColors.dark.muted);

    final pill = tester.widget<Text>(find.text('RESTART'));
    expect(pill.style?.color, KelolaColors.dark.amber);
  });

  testWidgets('action ServiceRow with no status omits the health dot',
      (tester) async {
    await tester.pumpWidget(
      pumpRow(
        ServiceRow(
          risk: RiskLevel.destructive,
          name: 'Reboot',
          meta: 'destructive · SSH will drop',
          onTap: () {},
        ),
      ),
    );

    expect(statusDotFinder(), findsNothing);
    final band = tester.widget<RiskBand>(find.byType(RiskBand));
    expect(band.risk, RiskLevel.destructive);
    expect(band.status, isNull);
  });

  testWidgets('object ServiceRow with status still paints the health dot',
      (tester) async {
    await tester.pumpWidget(
      pumpRow(
        const ServiceRow(
          risk: RiskLevel.destructive,
          status: HealthStatus.healthy,
          name: 'apache2.service',
          meta: 'active · 47d',
          pillText: 'stop',
        ),
      ),
    );

    final dot = tester.widget<Container>(statusDotFinder());
    expect((dot.decoration as BoxDecoration).color, KelolaColors.dark.green);
  });

  testWidgets('StatCard meter uses HealthStatus, not RiskLevel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: const Scaffold(
          body: StatCard(
            label: 'Disk /',
            value: '78',
            unit: '%',
            meterFraction: 0.78,
            status: HealthStatus.warning,
          ),
        ),
      ),
    );

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.color, KelolaColors.dark.amber);
  });
}
