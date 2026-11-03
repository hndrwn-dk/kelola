import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/k8s/service_forward.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';
import 'package:kelola/presentation/screens/tunnels_screen.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/providers.dart';
import 'package:uuid/uuid.dart';

/// What Kubernetes home last read. Detail screens resolve links (pod,
/// claim, volume) against it and never open their own SSH session.
class K8sSnapshot {
  const K8sSnapshot({
    required this.hostId,
    required this.workloads,
    this.host,
    this.facts,
    this.storage,
    this.readAt,
    this.now,
  });

  final String hostId;
  final Host? host;
  final HostFacts? facts;
  final List<K8sWorkload> workloads;
  final K8sStorage? storage;
  final DateTime? readAt;

  /// Test seam. Production uses the wall clock.
  final DateTime Function()? now;

  String get asOf {
    final age = k8sAge(readAt, now?.call() ?? DateTime.now().toUtc());
    return age.isEmpty ? 'snapshot' : 'as of $age ago';
  }

  K8sWorkload? pod(String namespace, String name) {
    for (final w in workloads) {
      if (w.kind == K8sKind.pod && w.namespace == namespace && w.name == name) {
        return w;
      }
    }
    return null;
  }

  /// Pods whose spec mounts [claim]. Pods, not templates: StatefulSet
  /// claims are generated and only the Pod names them.
  List<K8sWorkload> podsMounting(K8sVolumeClaim claim) {
    return [
      for (final w in workloads)
        if (w.kind == K8sKind.pod &&
            w.namespace == claim.namespace &&
            (w.config?.claims.contains(claim.name) ?? false))
          w,
    ];
  }

  K8sVolumeClaim? claim(String title) {
    for (final c in storage?.claims ?? const <K8sVolumeClaim>[]) {
      if (c.title == title) {
        return c;
      }
    }
    return null;
  }

  K8sPersistentVolume? volume(String name) {
    if (name.isEmpty) {
      return null;
    }
    for (final v in storage?.volumes ?? const <K8sPersistentVolume>[]) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }

  bool get canOpenWorkload => host != null && facts != null;

  void openWorkload(BuildContext context, K8sWorkload row) {
    final h = host;
    final f = facts;
    if (h == null || f == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkloadDetailScreen(host: h, facts: f, workload: row),
      ),
    );
  }

  void openClaim(BuildContext context, K8sVolumeClaim claim) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => K8sClaimDetailScreen(snapshot: this, claim: claim),
      ),
    );
  }

  void openVolume(BuildContext context, K8sPersistentVolume volume) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => K8sVolumeDetailScreen(snapshot: this, volume: volume),
      ),
    );
  }
}

class K8sServiceDetailScreen extends ConsumerWidget {
  const K8sServiceDetailScreen({
    super.key,
    required this.snapshot,
    required this.service,
    this.openTunnels,
  });

  final K8sSnapshot snapshot;
  final K8sService service;

  /// Test seam. Production pushes the host's Tunnels screen.
  final void Function(BuildContext context, String hostId)? openTunnels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = service;
    final c = context.kc;
    return _DetailScaffold(
      snapshot: snapshot,
      title: s.title,
      children: [
        RiskBand.forHealth(
          status: s.health,
          child: _facts([
            ('Type', s.type),
            if (s.clusterIp.isNotEmpty) ('Cluster IP', s.clusterIp),
            if (s.externalAddress.isNotEmpty)
              (s.type == 'ExternalName' ? 'External name' : 'External', s.externalAddress),
            if (s.loadBalancerPending) ('External', 'LB pending'),
            ('Selector', s.selector.isEmpty ? 'none' : s.selectorLabel),
            ('Endpoints', s.endpointsLabel),
          ]),
        ),
        if (s.portList.isNotEmpty) ...[
          const SizedBox(height: 10),
          const SectionSlab('Ports'),
          for (final p in s.portList) ...[
            ServiceRow(risk: RiskLevel.read, name: p.label, meta: _portMeta(p)),
            const SizedBox(height: 6),
          ],
          for (final p in forwardablePorts(s)) ...[
            ServiceRow(
              risk: RiskLevel.read,
              name: 'Forward ${p.port}/TCP',
              meta: 'pro · kubectl port-forward',
              onTap: () => _forward(context, ref, p),
            ),
            const SizedBox(height: 6),
          ],
        ],
        if (s.hasSelector) ...[
          const SizedBox(height: 10),
          const SectionSlab('Endpoints'),
          if (s.addresses.isEmpty)
            K8sQuietNote('No pod matches this selector. Check the pod labels '
                'against ${s.selectorLabel}.')
          else ...[
            if (s.noEndpoints)
              K8sQuietNote('No ready endpoints. Pods match, but none pass '
                  'readiness.'),
            for (final a in s.addresses) ...[
              _endpointRow(context, a),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ],
    );
  }

  /// Saves (or reuses) a kubectl tunnel target and opens Tunnels, where
  /// the user starts it. Locked builds show the tunnels explainer only.
  Future<void> _forward(
    BuildContext context,
    WidgetRef ref,
    K8sServicePort port,
  ) async {
    final entitlement = ref.read(entitlementProvider);
    if (!entitlement.isUnlocked(ProFeature.tunnels)) {
      await showTunnelsLockedExplainer(
        context,
        priceLabel: entitlement.priceLabel,
        onPurchase: () => entitlement.purchase(),
      );
      return;
    }
    final repo = ref.read(tunnelRepositoryProvider);
    final target = serviceForwardTarget(
      hostId: snapshot.hostId,
      service: service,
      port: port,
      saved: await repo.listForHost(snapshot.hostId),
      newId: () => const Uuid().v7(),
    );
    await repo.upsert(target);
    if (!context.mounted) {
      return;
    }
    final open = openTunnels;
    if (open != null) {
      open(context, snapshot.hostId);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TunnelsScreen(hostId: snapshot.hostId),
      ),
    );
  }

  String _portMeta(K8sServicePort p) {
    return [
      'port ${p.port}',
      if (p.nodePort != null) 'nodePort ${p.nodePort}',
      if (p.targetPort.isNotEmpty) 'target ${p.targetPort}',
    ].join(' · ');
  }

  Widget _endpointRow(BuildContext context, K8sEndpointAddress a) {
    final pod = a.targetKind == 'Pod'
        ? snapshot.pod(a.targetNamespace, a.targetName)
        : null;
    return ServiceRow(
      risk: RiskLevel.read,
      status: a.ready ? HealthStatus.healthy : HealthStatus.warning,
      name: a.targetName.isEmpty ? a.ip : a.targetName,
      meta: [
        a.ready ? 'ready' : 'not ready',
        if (a.targetName.isNotEmpty) a.ip,
        if (a.nodeName.isNotEmpty) a.nodeName,
      ].join(' · '),
      onTap: pod == null || !snapshot.canOpenWorkload
          ? null
          : () => snapshot.openWorkload(context, pod),
    );
  }
}

class K8sClaimDetailScreen extends ConsumerWidget {
  const K8sClaimDetailScreen({
    super.key,
    required this.snapshot,
    required this.claim,
  });

  final K8sSnapshot snapshot;
  final K8sVolumeClaim claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pvc = claim;
    final c = context.kc;
    final volume = snapshot.volume(pvc.volumeName);
    final pods = snapshot.podsMounting(pvc);
    return _DetailScaffold(
      snapshot: snapshot,
      title: pvc.title,
      children: [
        RiskBand.forHealth(
          status: pvc.health,
          child: _facts([
            ('Phase', pvc.phase.isEmpty ? 'unknown' : pvc.phase),
            ('Requested', pvc.requested.isEmpty ? '-' : pvc.requested),
            ('Capacity', pvc.capacity.isEmpty ? '-' : pvc.capacity),
            ('Class', pvc.storageClass.isEmpty ? '-' : pvc.storageClass),
            if (pvc.accessModes.isNotEmpty) ('Access', pvc.accessModesLabel),
          ]),
        ),
        const SizedBox(height: 10),
        const SectionSlab('Volume'),
        if (pvc.volumeName.isEmpty)
          K8sQuietNote('Not bound to a volume yet.')
        else
          ServiceRow(
            risk: RiskLevel.read,
            status: volume?.health,
            name: pvc.volumeName,
            meta: volume == null
                ? 'not in this snapshot'
                : [
                    'pv',
                    volume.phase.isEmpty ? 'unknown' : volume.phase,
                    if (volume.capacity.isNotEmpty) volume.capacity,
                  ].join(' · '),
            onTap: volume == null
                ? null
                : () => snapshot.openVolume(context, volume),
          ),
        const SizedBox(height: 10),
        const SectionSlab('Mounted by'),
        if (pods.isEmpty)
          K8sQuietNote('Not mounted by any pod.')
        else
          for (final p in pods) ...[
            ServiceRow(
              risk: RiskLevel.read,
              status: p.health,
              name: p.name,
              meta: [
                'pod',
                if (p.phase.isNotEmpty) p.phase,
                p.readyLabel,
              ].join(' · '),
              onTap: snapshot.canOpenWorkload
                  ? () => snapshot.openWorkload(context, p)
                  : null,
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class K8sVolumeDetailScreen extends ConsumerWidget {
  const K8sVolumeDetailScreen({
    super.key,
    required this.snapshot,
    required this.volume,
  });

  final K8sSnapshot snapshot;
  final K8sPersistentVolume volume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pv = volume;
    final c = context.kc;
    final claim = pv.claim.isEmpty ? null : snapshot.claim(pv.claim);
    return _DetailScaffold(
      snapshot: snapshot,
      title: pv.name,
      children: [
        RiskBand.forHealth(
          status: pv.health,
          child: _facts([
            ('Phase', pv.phase.isEmpty ? 'unknown' : pv.phase),
            ('Capacity', pv.capacity.isEmpty ? '-' : pv.capacity),
            ('Reclaim', pv.reclaimPolicy.isEmpty ? '-' : pv.reclaimPolicy),
            ('Class', pv.storageClass.isEmpty ? '-' : pv.storageClass),
            if (pv.accessModes.isNotEmpty) ('Access', pv.accessModesLabel),
          ]),
        ),
        const SizedBox(height: 10),
        const SectionSlab('Claim'),
        if (pv.claim.isEmpty)
          K8sQuietNote('No claim. The volume is available.')
        else
          ServiceRow(
            risk: RiskLevel.read,
            status: claim?.health,
            name: pv.claim,
            meta: claim == null
                ? (pv.phase == 'Released'
                    ? 'claim deleted; volume released'
                    : 'not in this snapshot')
                : [
                    'pvc',
                    claim.phase.isEmpty ? 'unknown' : claim.phase,
                  ].join(' · '),
            onTap: claim == null
                ? null
                : () => snapshot.openClaim(context, claim),
          ),
      ],
    );
  }
}

class _DetailScaffold extends ConsumerWidget {
  const _DetailScaffold({
    required this.snapshot,
    required this.title,
    required this.children,
  });

  final K8sSnapshot snapshot;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, snapshot.hostId),
        title: title,
        contextLine: snapshot.asOf,
      ),
      body: ListView(
        padding: kelolaScrollPadding(context),
        children: children,
      ),
    );
  }
}

/// Label/value rows inside a band. Values come from the server, so mono.
Widget _facts(List<(String, String)> rows) {
  return FactGroup(
    heading: null,
    framed: false,
    entries: [for (final r in rows) FactEntry(label: r.$1, value: r.$2)],
  );
}
