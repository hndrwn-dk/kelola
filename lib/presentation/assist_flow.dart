import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/llm/assist_service.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/presentation/widgets/assist_preview_sheet.dart';
import 'package:kelola/providers.dart';

Future<LlmSettings> requireAssistSettings(WidgetRef ref) async {
  final settings = await ref.read(llmSettingsProvider.future);
  if (!settings.provider.enabled || !settings.isConfigured) {
    throw StateError(
      settings.provider.enabled
          ? 'Assist provider is not configured. Open Assist and finish base URL / model${settings.provider == LlmProvider.openaiCompatible ? ' / API key' : ''}.'
          : 'Configure Assist first (provider is None).',
    );
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

final _assistResult = ValueNotifier<({String title, String body})?>(null);
var _assistResultSheetOpen = false;

/// Shows Assist output. A second call replaces the open sheet instead of stacking.
Future<void> showAssistResult(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  _assistResult.value = (title: title, body: body);
  if (_assistResultSheetOpen) {
    return;
  }
  _assistResultSheetOpen = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (ctx) {
        return ValueListenableBuilder<({String title, String body})?>(
          valueListenable: _assistResult,
          builder: (context, data, _) {
            final c = context.kc;
            final titleText = data?.title ?? title;
            final bodyText = data?.body ?? body;
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
                      Text(
                        titleText,
                        style: KelolaType.display(color: c.text, size: 16),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: SingleChildScrollView(
                          child: SelectionArea(
                            child: Text(
                              bodyText,
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
      },
    );
  } finally {
    _assistResultSheetOpen = false;
    _assistResult.value = null;
  }
}
