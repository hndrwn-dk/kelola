import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/openshift_health.dart';

/// M48: read-only ClusterOperator detail. The three conditions with reason
/// and message, all server text in mono. No actions.
Future<void> showOcpOperatorSheet(
  BuildContext context, {
  required ClusterOperatorState operator,
  String asOf = '',
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) => OcpOperatorSheetBody(operator: operator, asOf: asOf),
  );
}

class OcpOperatorSheetBody extends StatelessWidget {
  const OcpOperatorSheetBody({
    super.key,
    required this.operator,
    this.asOf = '',
  });

  final ClusterOperatorState operator;

  /// Age of the read this came from, e.g. `3m`. Empty when unknown.
  final String asOf;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final maxBody = kelolaSheetMaxBodyHeight(context);
    final meta = [
      if (operator.version.isNotEmpty) operator.version,
      asOf.isEmpty ? 'snapshot' : 'as of $asOf ago',
    ].join(' · ');
    return KelolaSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KelolaSheetDragHandle(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          operator.name,
                          style: KelolaType.mono(color: c.text, size: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          meta,
                          style: KelolaType.mono(color: c.muted, size: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                KelolaChromeIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (maxBody * 0.7).clamp(120.0, maxBody),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final type in const [
                      'Available',
                      'Progressing',
                      'Degraded',
                    ]) ...[
                      _condition(context, type, operator.condition(type)),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _condition(BuildContext context, String type, OcpCondition? cond) {
    final status = _status(type, cond);
    return RiskBand.forHealth(
      status: status,
      child: FactGroup(
        heading: null,
        framed: false,
        entries: [
          FactEntry(label: type, value: cond?.statusLabel ?? 'not reported'),
          if (cond != null && cond.reason.isNotEmpty)
            FactEntry(label: 'Reason', value: cond.reason),
          if (cond != null && cond.message.isNotEmpty)
            FactEntry(label: 'Message', value: cond.message),
        ],
      ),
    );
  }

  /// Colour carries meaning only: red for the failing condition, green
  /// for a healthy one, grey otherwise.
  HealthStatus _status(String type, OcpCondition? cond) {
    final v = cond?.status;
    if (v == null) {
      return HealthStatus.unknown;
    }
    return switch (type) {
      'Available' => v ? HealthStatus.healthy : HealthStatus.failed,
      'Degraded' => v ? HealthStatus.failed : HealthStatus.healthy,
      _ => HealthStatus.unknown,
    };
  }
}
