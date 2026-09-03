import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/correlation.dart';
import 'package:kelola/domain/incident/incident_sheet.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/presentation/widgets/incident_sheet.dart';

void main() {
  testWidgets('pill tap is distinct from row tap', (tester) async {
    var pill = 0;
    var row = 0;
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: ServiceRow(
            risk: RiskLevel.read,
            status: HealthStatus.failed,
            name: 'nas-01',
            meta: '10.0.0.8',
            pillText: '2 failed',
            onTap: () => row++,
            onPillTap: () => pill++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('2 FAILED'));
    await tester.pump();
    expect(pill, 1);
    expect(row, 0);
  });

  testWidgets('incident sheet renders cache and look-up without a spinner',
      (tester) async {
    const host = Host(
      id: 'h1',
      alias: 'nas-01',
      address: '10.0.0.8',
      port: 22,
      username: 'hendra',
      keyAlias: 'k',
      attention: HostAttention.failedUnits,
      failedUnitCount: 1,
    );
    final view = buildIncidentSheet(
      host: host,
      cache: CorrelationSnapshot(
        failedUnitNames: const ['nginx.service'],
        journalByUnit: {
          'nginx.service': [
            JournalEntry(
              cursor: '1',
              realtimeUsec: '1000',
              priority: 3,
              message: 'emerg bind',
              unit: 'nginx.service',
            ),
          ],
        },
      ),
    );
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showIncidentSheet(
                  context,
                  host: host,
                  view: view,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('nginx.service'), findsWidgets);
    expect(find.text('Restart'), findsOneWidget);
    expect(find.byType(JournalLogLine), findsOneWidget);
    expect(find.textContaining('not in cache'), findsOneWidget);
  });
}
