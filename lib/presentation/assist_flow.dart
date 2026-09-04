import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/llm/assist_service.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/presentation/widgets/assist_preview_sheet.dart';
import 'package:kelola/providers.dart';

Future<LlmSettings> requireAssistSettings(WidgetRef ref) async {
  final settings = await ref.read(llmSettingsProvider.future);
  if (!settings.provider.enabled || !settings.isConfigured) {
    throw StateError('Configure Assist first (provider is None).');
  }
  return settings;
}

Future<T?> runAssistWithPreview<T>({
  required BuildContext context,
  required WidgetRef ref,
  required LlmSettings settings,
  required AssistRequest request,
  required Future<T> Function(AssistService service) run,
}) async {
  final service = ref.read(assistServiceProvider);
  if (service.needsCloudPreview(settings)) {
    final preview = service.previewPayload(request);
    final ok = await showAssistPreviewSheet(context, preview: preview);
    if (!ok) {
      return null;
    }
    service.approveCloudPreview();
  }
  return run(service);
}

Future<void> showAssistResult(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 24, 14, 28),
        child: RiskBand(
          risk: RiskLevel.read,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: KelolaType.display(color: c.text, size: 16)),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: Text(
                        body,
                        style: KelolaType.body(color: c.text, size: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Close',
                  meta: 'assist only · nothing ran',
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
