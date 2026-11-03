import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;

/// One row on a Wave 2 list (event, service, claim, volume).
class K8sListRow {
  const K8sListRow({
    required this.name,
    required this.meta,
    required this.status,
    this.detail,
    this.onTap,
  });

  final String name;
  final String meta;
  final HealthStatus status;

  /// Long server text (event message). Rendered under the row.
  final String? detail;
  final VoidCallback? onTap;
}

/// [K8sListRow]s as [ServiceRow]s, at most [limit] of them. Shared by the
/// home sections and the full list so a row looks the same in both.
class K8sRows extends StatelessWidget {
  const K8sRows({super.key, required this.rows, this.limit});

  final List<K8sListRow> rows;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final shown = limit == null ? rows : rows.take(limit!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in shown) ...[
          ServiceRow(
            risk: RiskLevel.read,
            status: row.status,
            name: row.name,
            meta: row.meta,
            detail: row.detail,
            onTap: row.onTap,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

/// Muted human copy for "nothing here" / explanations on k8s screens.
class K8sQuietNote extends StatelessWidget {
  const K8sQuietNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: KelolaType.body(color: context.kc.muted, size: 13)),
    );
  }
}

/// Read-only snapshot list opened from the Kubernetes home sections.
/// Rows come from the probe the home screen already ran; pull to go back
/// and refresh there, so this screen never opens its own SSH session.
class K8sResourceListScreen extends ConsumerStatefulWidget {
  const K8sResourceListScreen({
    super.key,
    required this.hostId,
    required this.title,
    required this.rows,
    this.emptyCopy = 'Nothing to show.',
  });

  final String hostId;
  final String title;
  final List<K8sListRow> rows;
  final String emptyCopy;

  @override
  ConsumerState<K8sResourceListScreen> createState() =>
      _K8sResourceListScreenState();
}

class _K8sResourceListScreenState extends ConsumerState<K8sResourceListScreen> {
  bool _problemsOnly = false;

  @override
  Widget build(BuildContext context) {
    final rows = _problemsOnly
        ? [
            for (final r in widget.rows)
              if (r.status != HealthStatus.healthy) r,
          ]
        : widget.rows;
    final problems =
        widget.rows.where((r) => r.status != HealthStatus.healthy).length;
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.hostId),
        title: widget.title,
        contextLine: '${widget.rows.length} total',
      ),
      body: ListView(
        padding: kelolaScrollPadding(context),
        children: [
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              FilterPill(
                label: 'All ${widget.rows.length}',
                selected: !_problemsOnly,
                onTap: () => setState(() => _problemsOnly = false),
              ),
              FilterPill(
                label: 'Problems $problems',
                selected: _problemsOnly,
                onTap: () => setState(() => _problemsOnly = true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            KelolaEmpty(body: widget.emptyCopy)
          else
            K8sRows(rows: rows),
        ],
      ),
    );
  }
}
