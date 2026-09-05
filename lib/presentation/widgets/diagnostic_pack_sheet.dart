import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/diagnostic_pack.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/probes/df_pt_probe.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/providers.dart';
import 'package:share_plus/share_plus.dart';

typedef DiagnosticShare = Future<void> Function(String text);

Future<void> showDiagnosticPackPreview(
  BuildContext context, {
  required String pack,
  DiagnosticShare? share,
  String? error,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return KelolaSheet(
        child: _DiagnosticPackPanel(
          pack: pack,
          error: error,
          share: share ?? _shareViaOs,
        ),
      );
    },
  );
}

Future<void> openDiagnosticPack(
  BuildContext context,
  WidgetRef ref,
  Host host,
) async {
  final repo = ref.read(hostRepositoryProvider);
  final facts = await repo.facts(host.id) ?? HostFacts.undiscovered;
  final store = ref.read(correlationStoreProvider);
  var failed = [...store.get(host.id).failedUnitNames];
  if (failed.isEmpty) {
    failed = await repo.listFailedUnitNames(host.id);
  }
  var journal = const <JournalEntry>[];
  var dfPt = '';
  String? error;
  if (context.mounted) {
    try {
      dfPt = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: facts,
        probe: const DfPtProbe(),
      );
    } catch (e) {
      error = describeSshError(e);
    }
  }
  if (context.mounted) {
    try {
      final page = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: facts,
        probe: const JournalProbe(limit: 50),
      );
      journal = page.entries;
    } catch (e) {
      final next = describeSshError(e);
      error = error == null ? next : '$error\n$next';
    }
  }
  if (!context.mounted) {
    return;
  }
  final pack = buildDiagnosticPack(
    host: host,
    facts: facts,
    failedUnits: failed,
    journal: journal,
    dfPt: dfPt,
  );
  await showDiagnosticPackPreview(context, pack: pack, error: error);
}

Future<void> _shareViaOs(String text) {
  return Share.share(text, subject: 'Kelola diagnostic pack');
}

class _DiagnosticPackPanel extends StatelessWidget {
  const _DiagnosticPackPanel({
    required this.pack,
    required this.share,
    this.error,
  });

  final String pack;
  final DiagnosticShare share;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KelolaRadii.lg),
        ),
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
            Text(
              'Diagnostic pack',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              'This is exactly what will leave the phone.',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              KelolaError(message: error!),
            ],
            const SizedBox(height: 12),
            RiskBand(
              risk: RiskLevel.read,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: SelectionArea(
                child: Text(
                  pack,
                  style: KelolaType.mono(color: c.text, size: 11),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ServiceRow(
              risk: RiskLevel.read,
              name: 'Share',
              meta: 'system share sheet',
              onTap: () async {
                await share(pack);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
            const SizedBox(height: 6),
            ServiceRow(
              risk: RiskLevel.read,
              name: 'Cancel',
              meta: 'nothing is shared',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
  }
}
