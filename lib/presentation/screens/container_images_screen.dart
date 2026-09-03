import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/containers/container_images.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/container_images_probe.dart';
import 'package:kelola/domain/probes/container_prune_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_container_action.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class ContainerImagesScreen extends ConsumerStatefulWidget {
  const ContainerImagesScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.engine,
  });

  final Host host;
  final HostFacts facts;
  final String engine;

  @override
  ConsumerState<ContainerImagesScreen> createState() =>
      _ContainerImagesScreenState();
}

class _ContainerImagesScreenState extends ConsumerState<ContainerImagesScreen> {
  ContainerImageInventory _inv = const ContainerImageInventory(images: []);
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final inv = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: ContainerImagesProbe(engine: widget.engine),
        facts: widget.facts,
      );
      setState(() => _inv = inv);
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _prune() async {
    final label = _inv.reclaimableLabel;
    if (label.isEmpty) {
      setState(() => _error = 'Reclaimable size unavailable; prune aborted.');
      return;
    }
    final ok = await confirmContainerPrune(
      context,
      hostAlias: widget.host.alias,
      reclaimableLabel: label,
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: ContainerPruneProbe(engine: widget.engine),
        facts: widget.facts,
      );
      await _load();
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
    final engine = widget.engine.toUpperCase();
    final reclaim = _inv.reclaimableLabel;

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Images',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              '$engine · ${_inv.images.length} IMAGES',
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                children: [
                  if (_error != null) ...[
                    KelolaError(
                      message: _error!,
                      sudoUser: widget.host.username,
                    ),
                    const SizedBox(height: 12),
                  ],
                  ServiceRow(
                    risk: RiskLevel.destructive,
                    name: 'Prune unused images',
                    meta: reclaim.isEmpty
                        ? 'destructive · reclaimable size unknown'
                        : 'destructive · reclaims $reclaim',
                    onTap: _busy ? null : _prune,
                  ),
                  const SizedBox(height: 12),
                  if (!_busy && _inv.images.isEmpty)
                    const KelolaEmpty(body: 'No images.'),
                  for (final img in _inv.images)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ServiceRow(
                        risk: RiskLevel.read,
                        name: img.tag.isEmpty
                            ? img.repository
                            : '${img.repository}:${img.tag}',
                        meta: img.id,
                        endValue: img.sizeLabel,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
