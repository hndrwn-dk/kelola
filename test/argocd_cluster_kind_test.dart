import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/k8s/cluster_kind_store.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';

ClusterHealth _read({
  bool? openShift = false,
  String ctx = 'prod',
  bool? argo,
  bool reachable = true,
}) =>
    ClusterHealth(
      apiReachable: reachable,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
      isOpenShift: openShift,
      kubeContext: ctx,
      hasArgo: argo,
    );

final _t0 = DateTime.utc(2026, 11, 10, 10);
final _t1 = DateTime.utc(2026, 11, 10, 11);

/// M49: the cluster-kind cache carries whether Argo CD is installed.
void main() {
  group('mergeClusterKind hasArgo', () {
    test('a read that found Argo CD stores it', () {
      final r = mergeClusterKind(null, _read(argo: true), _t0)!;
      expect(r.hasArgo, isTrue);
      expect(r.argoKnown, isTrue);
    });

    test('a null read keeps the previous value on the same context', () {
      final prev = mergeClusterKind(null, _read(argo: true), _t0)!;
      final next = mergeClusterKind(prev, _read(), _t1)!;
      expect(next.hasArgo, isTrue);
      expect(next.readAt, _t1);
    });

    test('a null read drops the previous value when the context changed', () {
      final prev = mergeClusterKind(null, _read(argo: true), _t0)!;
      final next = mergeClusterKind(prev, _read(ctx: 'other'), _t1)!;
      expect(next.hasArgo, isNull);
    });

    test('a read of false replaces a previous true', () {
      final prev = mergeClusterKind(null, _read(argo: true), _t0)!;
      final next = mergeClusterKind(prev, _read(argo: false), _t1)!;
      expect(next.hasArgo, isFalse);
    });

    test('an unknown-kind read keeps the previous value', () {
      final prev = mergeClusterKind(null, _read(argo: true), _t0)!;
      final next = mergeClusterKind(prev, _read(openShift: null), _t1)!;
      expect(next.hasArgo, isTrue);
      expect(next.readAt, _t0);
    });

    test('a newer read on another context makes argoKnown null', () {
      final prev = mergeClusterKind(null, _read(argo: true), _t0)!;
      final next =
          mergeClusterKind(prev, _read(openShift: null, ctx: 'other'), _t1)!;
      expect(next.seenContext, 'other');
      expect(next.hasArgo, isTrue);
      expect(next.argoKnown, isNull);
    });
  });

  test('withDistro keeps hasArgo', () {
    final prev = mergeClusterKind(null, _read(argo: true), _t0)!;
    final next = withDistro(prev, OpenShiftDistro.okd, _t1);
    expect(next.hasArgo, isTrue);
    expect(next.distro, OpenShiftDistro.okd);
  });

  group('ClusterKindStore', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kelola_argo_kind');
      file = File('${dir.path}/cluster_kind.json');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips argo through the file', () async {
      final store = ClusterKindStore(file);
      await store.recordRead('h1', _read(argo: true), _t0);
      expect(jsonDecode(file.readAsStringSync())['h1']['argo'], isTrue);
      final back = await ClusterKindStore(file).read('h1');
      expect(back!.hasArgo, isTrue);
    });

    test('argo false round-trips and null is omitted', () async {
      final store = ClusterKindStore(file);
      await store.recordRead('h1', _read(argo: false), _t0);
      await store.recordRead('h2', _read(), _t0);
      final json = jsonDecode(file.readAsStringSync()) as Map;
      expect(json['h1']['argo'], isFalse);
      expect((json['h2'] as Map).containsKey('argo'), isFalse);
    });

    test('old JSON without argo reads as unknown', () async {
      file.writeAsStringSync(
        jsonEncode({
          'h1': {
            'openShift': false,
            'at': _t0.toIso8601String(),
            'ctx': 'prod',
          },
        }),
      );
      final r = await ClusterKindStore(file).read('h1');
      expect(r!.hasArgo, isNull);
      expect(r.argoKnown, isNull);
    });

    test('a non-bool argo value reads as unknown', () async {
      file.writeAsStringSync(
        jsonEncode({
          'h1': {
            'openShift': false,
            'at': _t0.toIso8601String(),
            'argo': 'yes',
          },
        }),
      );
      expect((await ClusterKindStore(file).read('h1'))!.hasArgo, isNull);
    });
  });
}
