import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/data/llm/assist_service.dart';

Future<bool> showAssistPreviewSheet(
  BuildContext context, {
  required AssistPreview preview,
}) async {
  final c = context.kc;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
          top: 24,
        ),
        child: RiskBand(
          risk: RiskLevel.mutate,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Preview outbound prompt',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Exactly what will be sent to your configured provider.',
                  style: KelolaType.body(color: c.muted, size: 12),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: Text(
                        'SYSTEM\n${preview.system}\n\nUSER\n${preview.user}',
                        style: KelolaType.mono(color: c.text, size: 11),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ServiceRow(
                  risk: RiskLevel.mutate,
                  name: 'Send',
                  meta: 'approve this session',
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Cancel',
                  meta: 'nothing is sent',
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}
