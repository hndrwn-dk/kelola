import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

/// Screens that take a host and operate on it. A new file matching the
/// constructor pattern must use [KelolaHostAppBar] or this test fails.
final hostScopedScreenFiles = [
  'lib/presentation/screens/container_detail_screen.dart',
  'lib/presentation/screens/container_images_screen.dart',
  'lib/presentation/screens/containers_screen.dart',
  'lib/presentation/screens/disk_screen.dart',
  'lib/presentation/screens/edit_host_screen.dart',
  'lib/presentation/screens/enrollment_screen.dart',
  'lib/presentation/screens/file_editor_screen.dart',
  'lib/presentation/screens/files_screen.dart',
  'lib/presentation/screens/firewall_screen.dart',
  'lib/presentation/screens/host_dashboard_screen.dart',
  'lib/presentation/screens/host_details_screen.dart',
  'lib/presentation/screens/host_key_mismatch_screen.dart',
  'lib/presentation/screens/journal_screen.dart',
  'lib/presentation/screens/metrics_screen.dart',
  'lib/presentation/screens/network_screen.dart',
  'lib/presentation/screens/packages_screen.dart',
  'lib/presentation/screens/processes_screen.dart',
  'lib/presentation/screens/snippets_screen.dart',
  'lib/presentation/screens/tofu_screen.dart',
  'lib/presentation/screens/tunnels_screen.dart',
  'lib/presentation/screens/unit_detail_screen.dart',
  'lib/presentation/screens/units_screen.dart',
  'lib/presentation/screens/terminal_sheet.dart',
];

void main() {
  test('every host-scoped screen renders the shared host identity', () {
    final dir = Directory('lib/presentation/screens');
    final discovered = <String>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }
      final src = file.readAsStringSync();
      final takesHost = RegExp(
        r'required this\.(hostId|host|hostAlias)\b',
      ).hasMatch(src);
      if (!takesHost) {
        continue;
      }
      final normalized = file.path.replaceAll('\\', '/');
      final rel = normalized.substring(normalized.indexOf('lib/'));
      discovered.add(rel);
    }
    discovered.sort();
    final expected = [...hostScopedScreenFiles]..sort();
    expect(discovered, expected);

    for (final rel in discovered) {
      final src = File(rel).readAsStringSync();
      expect(
        src.contains('KelolaHostAppBar') || src.contains('KelolaHostIdentity'),
        isTrue,
        reason: '$rel operates on one host but does not show host identity',
      );
    }
  });

  test('back control is the shared arrow, not a chevron', () {
    final lib = Directory('lib');
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }
      final src = file.readAsStringSync();
      expect(
        src.contains('arrow_back_ios'),
        isFalse,
        reason: '${file.path} picks its own back icon',
      );
    }
    final button = File('lib/design/kelola_components.dart').readAsStringSync();
    expect(button, contains('Icons.arrow_back'));
    expect(button, contains('class KelolaBackButton'));
  });

  testWidgets('host app bar shows the hostname at title size', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: const Scaffold(
          appBar: KelolaHostAppBar(hostAlias: 'nas-01', title: 'Services'),
        ),
      ),
    );
    final alias = tester.widget<Text>(find.byKey(KelolaHostIdentity.aliasKey));
    expect(alias.data, 'nas-01');
    expect(alias.style?.fontSize, 16);
    expect(alias.style?.color, KelolaColors.dark.text);
    expect(find.text('Services'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });

  testWidgets('page title sits above the kicker', (tester) async {
    await tester.pumpWidget(
      const KelolaApp(
        home: KelolaPage(
          title: 'Add host',
          kicker: 'SSH ONLY · NO AGENT',
          body: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleTop = tester.getTopLeft(find.text('Add host')).dy;
    final kickerTop = tester.getTopLeft(find.text('SSH ONLY · NO AGENT')).dy;
    expect(titleTop, lessThan(kickerTop));
  });

  testWidgets('disk page content starts below the app bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: KelolaPage(
          title: 'Disk',
          bar: const KelolaHostAppBar(hostAlias: 'nas-01', title: 'Disk'),
          body: ListView(
            children: const [
              Text('mount-marker', key: Key('mount-marker')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final markerTop = tester.getTopLeft(find.byKey(const Key('mount-marker'))).dy;
    expect(markerTop, greaterThanOrEqualTo(barBottom - 0.5));
    expect(find.text('nas-01'), findsOneWidget);
    expect(find.text('DF THEN DU'), findsNothing);
  });
}
