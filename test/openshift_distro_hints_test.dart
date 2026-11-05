import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';

String _okd(String name) =>
    File('test/fixtures/openshift/okd/$name').readAsStringSync();
String _ocp(String name) =>
    File('test/fixtures/openshift/$name').readAsStringSync();

ClusterHealth _cluster(String nodes, {required bool openShift}) {
  return parseClusterHealth(
    [
      '---READYZ---',
      'ok',
      '---NODES---',
      nodes,
      '---OPENSHIFT---',
      openShift
          ? _ocp('synthetic_config_openshift_io_v1.json')
          : '---OPENSHIFT_NONE---',
      '---AUTH---',
    ].join('\n'),
  );
}

/// M48.1 §2: osImage and distro hints from JSON M48 already reads.
void main() {
  group('node osImage', () {
    test('kept from status.nodeInfo.osImage', () {
      final h = _cluster(_okd('nodes_scos.json'), openShift: true);
      expect(h.nodes.single.osImage, 'CentOS Stream CoreOS 417.9.202410150733-0');
      final f = _cluster(_okd('nodes_fcos.json'), openShift: true);
      expect(f.nodes.single.osImage, 'Fedora CoreOS 39.20240210.3.0');
    });

    test('missing nodeInfo reads as empty, no throw', () {
      final h = _cluster(
        '{"items":[{"metadata":{"name":"n1"},"status":{"conditions":[]}}]}',
        openShift: true,
      );
      expect(h.nodes.single.osImage, '');
      final junk = _cluster(
        '{"items":[{"metadata":{"name":"n1"},"status":{"nodeInfo":{"osImage":7}}}]}',
        openShift: true,
      );
      expect(junk.nodes.single.osImage, '');
    });
  });

  group('ClusterHealth.distroHint', () {
    test('OKD nodes hint OKD; RHCOS nodes hint OCP', () {
      expect(
        _cluster(_okd('nodes_scos.json'), openShift: true).distroHint,
        OpenShiftDistro.okd,
      );
      expect(
        _cluster(_okd('nodes_fcos.json'), openShift: true).distroHint,
        OpenShiftDistro.okd,
      );
      final rhcos = _cluster(
        '{"items":[{"metadata":{"name":"m"},"status":{"nodeInfo":{"osImage":"Red Hat Enterprise Linux CoreOS 417.94.202410090854-0"}}}]}',
        openShift: true,
      );
      expect(rhcos.distroHint, OpenShiftDistro.ocp);
    });

    test('null when the cluster is not known to be OpenShift', () {
      expect(
        _cluster(_okd('nodes_scos.json'), openShift: false).distroHint,
        isNull,
      );
      expect(
        const ClusterHealth(
          apiReachable: true,
          controlPlaneReady: 0,
          controlPlaneDesired: 0,
          nodes: [
            ClusterNodeMembership(
              name: 'n',
              ready: true,
              kubeletVersion: '',
              containerRuntime: '',
              osImage: 'Fedora CoreOS 39',
            ),
          ],
        ).distroHint,
        isNull,
      );
    });

    test('survives withCoreDns', () {
      final h = _cluster(_okd('nodes_scos.json'), openShift: true)
          .withCoreDns(true);
      expect(h.distroHint, OpenShiftDistro.okd);
    });
  });

  group('ClusterVersionState.distro', () {
    OpenShiftDistro? distroOf(String cv) =>
        parseOpenShiftHealth('---CLUSTERVERSION---\n$cv').version!.distro;

    test('OKD versions', () {
      expect(distroOf(_okd('clusterversion_scos.json')), OpenShiftDistro.okd);
      expect(distroOf(_okd('clusterversion_fcos.json')), OpenShiftDistro.okd);
    });

    test('OCP version', () {
      expect(
        distroOf(_ocp('synthetic_clusterversion_healthy.json')),
        OpenShiftDistro.ocp,
      );
    });

    test('channel and version read from the OKD fixture', () {
      final v = parseOpenShiftHealth(
        '---CLUSTERVERSION---\n${_okd('clusterversion_scos.json')}',
      ).version!;
      expect(v.version, '4.17.0-okd-scos.0');
      expect(v.channel, 'stable-scos-4');
    });
  });
}
