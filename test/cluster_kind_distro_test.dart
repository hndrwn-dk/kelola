import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/k8s/cluster_kind_store.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';

ClusterHealth _read({
  bool? openShift = true,
  String ctx = 'okd-admin',
  String osImage = '',
  bool reachable = true,
}) =>
    ClusterHealth(
      apiReachable: reachable,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
      isOpenShift: openShift,
      kubeContext: ctx,
      nodes: [
        ClusterNodeMembership(
          name: 'n',
          ready: true,
          kubeletVersion: '',
          containerRuntime: '',
          osImage: osImage,
        ),
      ],
    );

const _scos = 'CentOS Stream CoreOS 417.9.202410150733-0';
final _t0 = DateTime.utc(2026, 11, 5, 10);
final _t1 = DateTime.utc(2026, 11, 5, 11);

/// M48.1 §2: the cluster-kind cache carries the distro.
void main() {
  group('mergeClusterKind', () {
    test('authoritative read stores the distro hint', () {
      final r = mergeClusterKind(null, _read(osImage: _scos), _t0)!;
      expect(r.distro, OpenShiftDistro.okd);
      expect(r.isOpenShift, isTrue);
    });

    test('null hint keeps the previous distro on the same context', () {
      final prev = mergeClusterKind(null, _read(osImage: _scos), _t0)!;
      final next = mergeClusterKind(prev, _read(), _t1)!;
      expect(next.distro, OpenShiftDistro.okd);
      expect(next.readAt, _t1);
    });

    test('null hint drops the previous distro when the context changed', () {
      final prev = mergeClusterKind(null, _read(osImage: _scos), _t0)!;
      final next = mergeClusterKind(prev, _read(ctx: 'other'), _t1)!;
      expect(next.distro, isNull);
      expect(next.kubeContext, 'other');
    });

    test('a new hint replaces the previous distro', () {
      final prev = mergeClusterKind(null, _read(osImage: _scos), _t0)!;
      final next = mergeClusterKind(
        prev,
        _read(osImage: 'Red Hat Enterprise Linux CoreOS 417.94'),
        _t1,
      )!;
      expect(next.distro, OpenShiftDistro.ocp);
    });

    test('a non-authoritative read never changes the distro', () {
      final prev = mergeClusterKind(null, _read(osImage: _scos), _t0)!;
      final unknown = mergeClusterKind(prev, _read(openShift: null), _t1)!;
      expect(unknown.distro, OpenShiftDistro.okd);
      final down = mergeClusterKind(
        prev,
        _read(openShift: false, reachable: false, ctx: 'other'),
        _t1,
      )!;
      expect(down.distro, OpenShiftDistro.okd);
    });
  });

  group('ClusterKindStore', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kelola_distro');
      file = File('${dir.path}/cluster_kind.json');
    });

    tearDown(() => dir.delete(recursive: true));

    test('recordDistro updates only the distro', () async {
      final store = ClusterKindStore(file);
      await store.recordRead('h1', _read(), _t0);
      await store.recordDistro('h1', OpenShiftDistro.okd, _t1);
      final r = (await ClusterKindStore(file).read('h1'))!;
      expect(r.distro, OpenShiftDistro.okd);
      expect(r.isOpenShift, isTrue);
      expect(r.kubeContext, 'okd-admin');
      expect(r.readAt, _t0);
    });

    test('recordDistro without a record is a no-op', () async {
      final store = ClusterKindStore(file);
      await store.recordDistro('h1', OpenShiftDistro.okd, _t1);
      expect(await store.read('h1'), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('recordDistro older than the kind read is ignored', () async {
      final store = ClusterKindStore(file);
      await store.recordRead('h1', _read(osImage: _scos), _t1);
      await store.recordDistro('h1', OpenShiftDistro.ocp, _t0);
      expect((await store.read('h1'))!.distro, OpenShiftDistro.okd);
    });

    test('JSON round-trip with and without distro', () async {
      final store = ClusterKindStore(file);
      await store.write(
        'okd',
        ClusterKindRecord(
          isOpenShift: true,
          readAt: _t0,
          distro: OpenShiftDistro.okd,
        ),
      );
      await store.write(
        'plain',
        ClusterKindRecord(isOpenShift: true, readAt: _t0),
      );
      final raw = jsonDecode(file.readAsStringSync()) as Map;
      expect((raw['okd'] as Map)['distro'], 'okd');
      expect((raw['plain'] as Map).containsKey('distro'), isFalse);
      final again = ClusterKindStore(file);
      expect((await again.read('okd'))!.distro, OpenShiftDistro.okd);
      expect((await again.read('plain'))!.distro, isNull);
    });

    test('old file without distro, and an unknown distro string, read as null',
        () async {
      file.writeAsStringSync(
        jsonEncode({
          'old': {'openShift': true, 'at': '2026-11-04T10:00:00.000Z', 'ctx': ''},
          'odd': {
            'openShift': true,
            'at': '2026-11-04T10:00:00.000Z',
            'distro': 'microshift',
          },
        }),
      );
      final store = ClusterKindStore(file);
      expect((await store.read('old'))!.isOpenShift, isTrue);
      expect((await store.read('old'))!.distro, isNull);
      expect((await store.read('odd'))!.distro, isNull);
    });
  });
}
