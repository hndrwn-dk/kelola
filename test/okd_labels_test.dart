import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';

/// M48.1 §3: labels.
void main() {
  group('clusterKindLabel', () {
    test('four cases', () {
      expect(clusterKindLabel(true, distro: OpenShiftDistro.okd), 'OKD');
      expect(clusterKindLabel(true, distro: OpenShiftDistro.ocp), 'OpenShift');
      expect(clusterKindLabel(true), 'OpenShift');
      expect(clusterKindLabel(false, distro: OpenShiftDistro.okd), 'Kubernetes');
      expect(clusterKindLabel(null, distro: OpenShiftDistro.okd), 'Kubernetes');
      expect(clusterKindLabel(false), 'Kubernetes');
      expect(clusterKindLabel(null), 'Kubernetes');
    });
  });

  group('ClusterKindRecord.label', () {
    final at = DateTime.utc(2026, 11, 5, 10);

    test('passes the distro', () {
      expect(
        ClusterKindRecord(isOpenShift: true, readAt: at, distro: OpenShiftDistro.okd)
            .label,
        'OKD',
      );
      expect(
        ClusterKindRecord(isOpenShift: true, readAt: at).label,
        'OpenShift',
      );
    });

    test('still Kubernetes when the context no longer matches', () {
      expect(
        ClusterKindRecord(
          isOpenShift: true,
          readAt: at,
          distro: OpenShiftDistro.okd,
          kubeContext: 'okd',
          seenContext: 'other',
        ).label,
        'Kubernetes',
      );
    });
  });

  group('FleetOcpSummary distro', () {
    test('tileLine prefix OKD for OKD, OCP otherwise', () {
      expect(
        const FleetOcpSummary(
          version: '4.17.0-okd-scos.0',
          distro: OpenShiftDistro.okd,
        ).tileLine,
        'OKD 4.17.0-okd-scos.0',
      );
      expect(
        const FleetOcpSummary(
          version: '4.17.0-okd-scos.0',
          distro: OpenShiftDistro.okd,
          operatorsDegraded: 2,
        ).tileLine,
        'OKD 4.17.0-okd-scos.0 · 2 operators degraded',
      );
      expect(const FleetOcpSummary(version: '4.17.3').tileLine, 'OCP 4.17.3');
      expect(
        const FleetOcpSummary(version: '4.17.3', distro: OpenShiftDistro.ocp)
            .tileLine,
        'OCP 4.17.3',
      );
      expect(const FleetOcpSummary(distro: OpenShiftDistro.okd).tileLine, 'OKD');
    });

    test('tileValue unchanged by distro', () {
      expect(
        const FleetOcpSummary(
          version: '4.17.0-okd-scos.0',
          distro: OpenShiftDistro.okd,
        ).tileValue,
        '4.17.0-okd-scos.0',
      );
    });

    test('JSON round-trip with d; old JSON without d still parses', () {
      const okd = FleetOcpSummary(
        version: '4.17.0-okd-scos.0',
        distro: OpenShiftDistro.okd,
      );
      expect(okd.toJson()['d'], 'okd');
      expect(FleetOcpSummary.fromJson(okd.toJson())!.distro, OpenShiftDistro.okd);
      final old = FleetOcpSummary.fromJson({'v': '4.17.3', 'opDeg': 1})!;
      expect(old.distro, isNull);
      expect(old.tileLine, 'OCP 4.17.3 · 1 operator degraded');
      expect(
        FleetOcpSummary.fromJson({'v': '4.17.3', 'd': 'nope'})!.distro,
        isNull,
      );
      expect(const FleetOcpSummary(version: '4.17.3').toJson().containsKey('d'),
          isFalse);
    });
  });
}
