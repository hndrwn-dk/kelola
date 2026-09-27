import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/workload_action_probe.dart';
import 'package:kelola/presentation/widgets/confirm_workload_action.dart';

const _web = K8sWorkload(
  kind: K8sKind.deployment,
  namespace: 'prod',
  name: 'web',
  ready: 2,
  desired: 3,
);

void main() {
  Future<void> open(
    WidgetTester tester, {
    required WorkloadVerb verb,
    int? replicas,
  }) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmWorkloadAction(
                  context,
                  hostAlias: 'k3s-01',
                  workload: _web,
                  verb: verb,
                  replicas: replicas,
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

  testWidgets('restart uses mutate confirm; delete uses token sheet',
      (tester) async {
    await open(tester, verb: WorkloadVerb.restart);
    expect(find.byType(MutateConfirmDialog), findsOneWidget);
    expect(find.byType(DestructiveConfirmSheet), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await open(tester, verb: WorkloadVerb.delete);
    final sheet = tester.widget<DestructiveConfirmSheet>(
      find.byType(DestructiveConfirmSheet),
    );
    expect(sheet.confirmToken, 'prod/web');
    expect(find.byType(KelolaSheet), findsOneWidget);
  });
}
