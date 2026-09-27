import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/workload_exec_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/providers.dart';

Future<void> openWorkloadExecSheet(
  BuildContext context, {
  required Host host,
  required HostFacts facts,
  required K8sWorkload workload,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.kc.ink,
    builder: (ctx) => KelolaSheet(
      child: SizedBox(
        height: kelolaSheetBodyHeight(ctx),
        child: WorkloadExecSheet(
          host: host,
          facts: facts,
          workload: workload,
        ),
      ),
    ),
  );
}

class WorkloadExecSheet extends ConsumerStatefulWidget {
  const WorkloadExecSheet({
    super.key,
    required this.host,
    required this.facts,
    required this.workload,
  });

  final Host host;
  final HostFacts facts;
  final K8sWorkload workload;

  @override
  ConsumerState<WorkloadExecSheet> createState() => _WorkloadExecSheetState();
}

class _WorkloadExecSheetState extends ConsumerState<WorkloadExecSheet> {
  final _input = TextEditingController();
  String _out = '';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final line = _input.text.trim();
    if (line.isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final out = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: WorkloadExecProbe(workload: widget.workload, line: line),
        facts: widget.facts,
      );
      setState(() => _out = out);
    } on ReadOnlyViolation {
      setState(() => _error = 'This host is read-only.');
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Material(
      color: c.ink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.workload.title,
              style: KelolaType.mono(color: c.muted, size: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _input,
              enabled: !_busy,
              style: KelolaType.mono(color: c.text, size: 13),
              decoration: InputDecoration(
                hintText: 'One command in this pod',
                hintStyle: KelolaType.body(color: c.dim, size: 13),
                isDense: true,
              ),
              onSubmitted: (_) => _run(),
            ),
            const SizedBox(height: 8),
            ServiceRow(
              risk: RiskLevel.mutate,
              name: 'Run',
              meta: 'mutate · one-shot, no PTY',
              onTap: _busy ? null : _run,
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  minHeight: 1.5,
                  backgroundColor: c.surface,
                  color: c.amber,
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              KelolaError(
                message: _error!,
                sudoUser: widget.host.username,
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: RiskBand(
                risk: RiskLevel.mutate,
                child: SingleChildScrollView(
                  child: SelectableText(
                    _out.isEmpty ? '' : _out,
                    style: KelolaType.mono(color: c.muted, size: 10.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
