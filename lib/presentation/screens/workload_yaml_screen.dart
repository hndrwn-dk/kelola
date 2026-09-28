import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/k8s/workload_yaml.dart';
import 'package:kelola/domain/probes/workload_yaml_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/destructive_auth.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_workload_action.dart';
import 'package:kelola/providers.dart';

class WorkloadYamlScreen extends ConsumerStatefulWidget {
  const WorkloadYamlScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.workload,
    required this.initialYaml,
  });

  final Host host;
  final HostFacts facts;
  final K8sWorkload workload;
  final String initialYaml;

  @override
  ConsumerState<WorkloadYamlScreen> createState() => _WorkloadYamlScreenState();
}

class _WorkloadYamlScreenState extends ConsumerState<WorkloadYamlScreen> {
  late final TextEditingController _yaml;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _yaml = TextEditingController(text: widget.initialYaml);
  }

  @override
  void dispose() {
    _yaml.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final yaml = _yaml.text;
    try {
      assertYamlMatchesWorkload(yaml, widget.workload);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final diff = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: WorkloadYamlDiffProbe(workload: widget.workload, yaml: yaml),
        facts: widget.facts,
      );
      if (!mounted) {
        return;
      }
      final allowed = await confirmWorkloadYamlApply(
        context,
        hostAlias: widget.host.alias,
        workload: widget.workload,
        diff: diff,
      );
      if (!allowed || !mounted) {
        return;
      }
      await requireDestructivePresence(
        ref.read(hardwareSignerProvider),
        risk: RiskLevel.destructive,
        reason: 'apply ${widget.workload.title}',
      );
      if (!mounted) {
        return;
      }
      await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: WorkloadYamlApplyProbe(workload: widget.workload, yaml: yaml),
        facts: widget.facts,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on ReadOnlyViolation {
      setState(() => _error = 'This host is read-only.');
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final readOnly = widget.host.readOnly;
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: widget.host.alias,
        title: widget.workload.title,
        contextLine: '${widget.workload.kind.short} · YAML',
        actions: [
          if (!readOnly)
            FilledButton(
              onPressed: _busy ? null : _apply,
              style: FilledButton.styleFrom(
                backgroundColor: c.amber,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Apply',
                style: KelolaType.display(color: c.ink, size: 13),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_busy)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: KelolaError(
                message: _error!,
                sudoUser: widget.host.username,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: TextField(
                controller: _yaml,
                maxLines: null,
                expands: true,
                style: KelolaType.mono(color: c.text, size: 12),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surface,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: c.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.amber),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
