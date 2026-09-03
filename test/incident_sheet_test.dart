import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/correlation.dart';
import 'package:kelola/domain/incident/incident_sheet.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/network/network_snapshot.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/probes/unit_list_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/service_unit.dart';

Host _host({
  int failed = 2,
  int disk = 40,
  HostAttention attention = HostAttention.failedUnits,
}) {
  return Host(
    id: 'h1',
    alias: 'nas-01',
    address: '10.0.0.8',
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    attention: attention,
    failedUnitCount: failed,
    diskRootPercent: disk,
    attentionAt: DateTime.utc(2026, 9, 3, 8),
  );
}

ServiceUnit _failed(String name) {
  return ServiceUnit(
    name: name,
    description: '',
    load: 'loaded',
    active: 'failed',
    sub: 'failed',
  );
}

void main() {
  test('failed units and disk from cache become broken objects', () {
    final view = buildIncidentSheet(
      host: _host(disk: 91),
      cache: CorrelationSnapshot(
        failedUnitNames: const ['nginx.service', 'borgmatic.service'],
      ),
    );
    expect(view.broken.map((o) => o.name), [
      'nginx.service',
      'borgmatic.service',
      '/',
    ]);
    expect(view.actions.length, lessThanOrEqualTo(2));
    expect(view.actions.first.label, 'Restart');
    expect(view.actions.first.risk, RiskLevel.mutate);
  });

  test('restart is reachable for a failed unit without visiting the unit list',
      () {
    final view = buildIncidentSheet(
      host: _host(),
      cache: CorrelationSnapshot(
        failedUnitNames: const ['nginx.service'],
        units: [_failed('nginx.service')],
      ),
    );
    expect(view.actions.map((a) => a.id), contains(IncidentActionId.restart));
    expect(view.actions, hasLength(2));
    expect(view.actions[1].id, IncidentActionId.logs);
  });

  test('cache miss related is look up, not a spinner flag', () {
    final view = buildIncidentSheet(
      host: _host(),
      cache: const CorrelationSnapshot(
        failedUnitNames: ['nginx.service'],
      ),
    );
    expect(view.related.cached, isFalse);
    expect(view.related.meta, 'not in cache — look up');
    expect(view.related.lookUp, CorrelationLookUp.processes);
    expect(view.blocking, isFalse);
    expect(view.logsInCache, isFalse);
  });

  test('port maps to pid then unit when cache is warm', () {
    final hit = correlatePort(
      const ListenPort(proto: 'tcp', local: '0.0.0.0:80', process: 'nginx', pid: 412),
      CorrelationSnapshot(
        processes: const [
          ProcessRow(
            pid: 412,
            ppid: 1,
            user: 'www',
            cpu: 0,
            mem: 0,
            rssKb: 0,
            stat: 'S',
            command: 'nginx',
          ),
        ],
        units: [_failed('nginx.service')],
      ),
    );
    expect(hit.cached, isTrue);
    expect(hit.title, 'nginx.service');
    expect(hit.meta, contains('412'));
  });

  test('failed unit journal is pre-filtered to that unit and capped at 20', () {
    final lines = List.generate(
      25,
      (i) => JournalEntry(
        cursor: '$i',
        realtimeUsec: '${1000 + i}',
        priority: 3,
        message: 'line $i',
        unit: 'nginx.service',
      ),
    );
    final view = buildIncidentSheet(
      host: _host(),
      cache: CorrelationSnapshot(
        failedUnitNames: const ['nginx.service'],
        journalByUnit: {'nginx.service': lines},
      ),
    );
    expect(view.logsInCache, isTrue);
    expect(view.lines, hasLength(20));
    expect(view.lines.every((e) => e.unit == 'nginx.service'), isTrue);
  });

  test('restarting container correlates to stack and logs look-up', () {
    const row = ContainerRow(
      id: 'abc',
      names: 'web',
      image: 'nginx',
      state: 'restarting',
      status: 'Restarting (1)',
      composeProject: 'edge',
    );
    final view = buildIncidentSheet(
      host: _host(failed: 0, attention: HostAttention.healthy),
      cache: const CorrelationSnapshot(containers: [row]),
    );
    expect(view.broken.single.name, 'web');
    expect(view.related.cached, isTrue);
    expect(view.related.title, 'edge');
    expect(view.logsInCache, isFalse);
    expect(view.related.lookUp, isNull);
    expect(view.logsLookUp, CorrelationLookUp.containerLogs);
  });

  test('failed count without names does not restart a fake unit', () {
    final view = buildIncidentSheet(
      host: _host(),
      cache: const CorrelationSnapshot(),
    );
    expect(view.broken.single.summary, cacheMissLookUp);
    expect(view.actions, isEmpty);
    expect(view.related.lookUp, CorrelationLookUp.units);
    expect(view.blocking, isFalse);
  });

  test('unit list ingest fills failed names from isFailed', () {
    final store = CorrelationStore();
    store.ingest(
      'h1',
      const UnitListProbe(),
      UnitListResult(
        units: [
          _failed('nginx.service'),
          const ServiceUnit(
            name: 'sshd.service',
            description: '',
            load: 'loaded',
            active: 'active',
            sub: 'running',
          ),
        ],
        initSupported: true,
      ),
    );
    expect(store.get('h1').failedUnitNames, ['nginx.service']);
  });

  test('cached container logs become twenty sheet lines', () {
    const row = ContainerRow(
      id: 'abc',
      names: 'web',
      image: 'nginx',
      state: 'restarting',
      status: 'Restarting (1)',
      composeProject: 'edge',
    );
    final view = buildIncidentSheet(
      host: _host(failed: 0, attention: HostAttention.healthy),
      cache: CorrelationSnapshot(
        containers: const [row],
        containerLogs: {
          'web': List.generate(25, (i) => 'log $i'),
        },
      ),
    );
    expect(view.logsInCache, isTrue);
    expect(view.lines, hasLength(20));
    expect(view.lines.first.message, 'log 0');
  });

  test('sshd failed unit still offers restart as lockout mutate', () {
    final view = buildIncidentSheet(
      host: _host(),
      cache: CorrelationSnapshot(
        failedUnitNames: const ['sshd.service'],
        units: [_failed('sshd.service')],
      ),
    );
    expect(view.actions.first.id, IncidentActionId.restart);
    expect(view.actions.first.risk, RiskLevel.destructive);
  });
}
