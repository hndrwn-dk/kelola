import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/presentation/widgets/confirm_container_action.dart';

void main() {
  const plex = ContainerRow(
    id: 'abc',
    names: 'plex',
    image: 'linuxserver/plex',
    state: 'running',
    status: 'Up',
  );
  const sshfront = ContainerRow(
    id: 'sf1',
    names: 'sshfront',
    image: 'linuxserver/openssh-server',
    state: 'running',
    status: 'Up',
    publishedPorts: '2222',
  );

  DestructiveConfirmSheet sheetOf(WidgetTester tester) {
    return tester.widget<DestructiveConfirmSheet>(
      find.byType(DestructiveConfirmSheet),
    );
  }

  Future<void> open(
    WidgetTester tester, {
    required String hostAlias,
    required ContainerRow row,
    required ContainerVerb verb,
  }) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmContainerAction(
                  context,
                  hostAlias: hostAlias,
                  row: row,
                  verb: verb,
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
  }

  testWidgets('remove uses DestructiveConfirmSheet with container name token',
      (tester) async {
    await open(
      tester,
      hostAlias: 'nas-01',
      row: plex,
      verb: ContainerVerb.remove,
    );
    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(sheetOf(tester).confirmToken, 'plex');
    expect(find.textContaining('plex'), findsWidgets);
  });

  testWidgets('lockout stop token is container name, not hostname',
      (tester) async {
    await open(
      tester,
      hostAlias: 'east-worker-uat',
      row: sshfront,
      verb: ContainerVerb.stop,
    );
    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(sheetOf(tester).confirmToken, 'sshfront');
    expect(find.textContaining('end your session'), findsOneWidget);
    expect(find.textContaining('east-worker-uat'), findsWidgets);

    var confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'east-worker-uat');
    await tester.pump();
    confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'sshfront');
    await tester.pump();
    confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('lockout remove token is container name, not hostname',
      (tester) async {
    await open(
      tester,
      hostAlias: 'east-worker-uat',
      row: sshfront,
      verb: ContainerVerb.remove,
    );
    expect(sheetOf(tester).confirmToken, 'sshfront');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('non-lockout restart stays a mutate dialog', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmContainerAction(
                  context,
                  hostAlias: 'nas-01',
                  row: plex,
                  verb: ContainerVerb.restart,
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
    expect(find.byType(MutateConfirmDialog), findsOneWidget);
    expect(find.byType(DestructiveConfirmSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('prune shows reclaimable size before confirming', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmContainerPrune(
                  context,
                  hostAlias: 'nas-01',
                  reclaimableLabel: '1.234GB',
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
    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('1.234GB'), findsWidgets);
  });
}
