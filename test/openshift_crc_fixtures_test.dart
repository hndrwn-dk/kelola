import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/coreos_node.dart';
import 'package:kelola/domain/k8s/openshift_health.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';

/// M48 §6: fixtures captured from CRC. Each test skips until its file is
/// dropped into test/fixtures/openshift/ (see README.md there).
String? _crc(String name) {
  final f = File('test/fixtures/openshift/$name');
  return f.existsSync() ? f.readAsStringSync() : null;
}

Object _skip(String? raw, String name) =>
    raw == null ? 'TODO: capture $name from CRC' : false;

void main() {
  final cv = _crc('clusterversion.json');
  final co = _crc('clusteroperators.json');
  final mcp = _crc('machineconfigpools.json');
  final csr = _crc('csr.json');
  final nodes = _crc('nodes.json');
  final api = _crc('config_openshift_io_v1.json');
  final ostree = _crc('rpm_ostree_status.json');

  test('clusterversion.json parses with a version and channel', () {
    final h = parseOpenShiftHealth('---CLUSTERVERSION---\n$cv');
    expect(h.sectionErrors.containsKey(OcpSection.clusterVersion), isFalse);
    expect(h.version!.version, isNotEmpty);
  }, skip: _skip(cv, 'clusterversion.json'));

  test('clusteroperators.json parses every operator', () {
    final h = parseOpenShiftHealth('---CLUSTEROPERATORS---\n$co');
    expect(h.operators, isNotEmpty);
    expect(h.operators!.every((o) => o.name.isNotEmpty), isTrue);
  }, skip: _skip(co, 'clusteroperators.json'));

  test('machineconfigpools.json parses master and worker', () {
    final h = parseOpenShiftHealth('---MCP---\n$mcp');
    expect(h.pools!.map((p) => p.name), containsAll(['master', 'worker']));
  }, skip: _skip(mcp, 'machineconfigpools.json'));

  test('csr.json parses', () {
    final h = parseOpenShiftHealth('---CSR---\n$csr');
    expect(h.csrs, isNotNull);
  }, skip: _skip(csr, 'csr.json'));

  test('nodes.json carries MCD state and roles', () {
    final h = parseClusterHealth('---NODES---\n$nodes');
    expect(h.nodes, isNotEmpty);
    expect(h.nodes.first.mcdState, isNotNull);
    expect(h.nodes.first.roles, isNotEmpty);
  }, skip: _skip(nodes, 'nodes.json'));

  test('config_openshift_io_v1.json says OpenShift', () {
    final h = parseClusterHealth('---OPENSHIFT---\n$api\n---AUTH---\n');
    expect(h.isOpenShift, isTrue);
  }, skip: _skip(api, 'config_openshift_io_v1.json'));

  test('rpm_ostree_status.json has a booted version', () {
    final s = parseCoreOsNode('---OSTREE---\n$ostree');
    expect(s.ostreeRead, isTrue);
    expect(s.bootedVersion, isNotEmpty);
  }, skip: _skip(ostree, 'rpm_ostree_status.json'));
}
