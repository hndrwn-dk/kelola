import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_list_view.dart';
import 'package:kelola/domain/containers/container_row.dart';

ContainerRow _row({
  required String names,
  String image = 'nginx',
  String state = 'running',
  String status = 'Up',
  String ports = '',
  String publishedPorts = '',
  String composeProject = '',
  String engine = 'docker',
  int? exitCode,
}) {
  return ContainerRow(
    id: names,
    names: names,
    image: image,
    state: state,
    status: status,
    ports: ports,
    publishedPorts: publishedPorts,
    composeProject: composeProject,
    engine: engine,
    exitCode: exitCode,
  );
}

void main() {
  final plex = _row(
    names: 'plex',
    image: 'linuxserver/plex',
    publishedPorts: '32787\u219232400',
    composeProject: 'media',
    status: 'Up 12 days (healthy)',
  );
  final transmission = _row(
    names: 'transmission',
    image: 'linuxserver/transmission',
    state: 'restarting',
    status: 'Restarting (1) 4 seconds ago',
    composeProject: 'media',
  );
  final unhealthy = _row(
    names: 'web',
    image: 'nginx',
    status: 'Up 3 minutes (unhealthy)',
    composeProject: 'infra',
  );
  final watchtower = _row(
    names: 'watchtower',
    image: 'containrrr/watchtower',
    state: 'exited',
    status: 'Exited (0) 3 days ago',
    exitCode: 0,
  );
  final crashed = _row(
    names: 'job',
    image: 'busybox',
    state: 'exited',
    status: 'Exited (1) 9 minutes ago',
    exitCode: 1,
  );
  final all = [plex, transmission, unhealthy, watchtower, crashed];

  test('chips filter, never sort: UNHEALTHY is a pure subset', () {
    final view = ContainerListView.build(all, ContainerListFilter.unhealthy);
    expect(view.rows.map((r) => r.names), ['transmission', 'web']);
    expect(view.rows, isNot(contains(plex)));
    expect(view.rows, isNot(contains(watchtower)));
  });

  test('empty UNHEALTHY filter is empty, no fallback list', () {
    final healthy = [plex, watchtower];
    final view =
        ContainerListView.build(healthy, ContainerListFilter.unhealthy);
    expect(view.isEmpty, isTrue);
    expect(view.rows, isEmpty);
    expect(
      containerListEmptyCopy(ContainerListFilter.unhealthy),
      'No unhealthy containers.',
    );
  });

  test('RUNNING and STOPPED are filters, not sorts', () {
    final running =
        ContainerListView.build(all, ContainerListFilter.running);
    expect(running.rows.map((r) => r.names), ['plex', 'web']);
    final stopped =
        ContainerListView.build(all, ContainerListFilter.stopped);
    expect(stopped.rows.map((r) => r.names), ['watchtower', 'job']);
    expect(stopped.rows.any((r) => r.running), isFalse);
  });

  test('chip counts are inventory totals', () {
    final counts = ContainerListCounts.from(all);
    expect(counts.running, 2);
    expect(counts.stopped, 2);
    expect(counts.unhealthy, 2);
    expect(counts.all, 5);
    expect(containerListChipLabel(ContainerListFilter.running, counts),
        'Running 2');
    expect(containerListChipLabel(ContainerListFilter.stopped, counts),
        'Stopped 2');
    expect(containerListChipLabel(ContainerListFilter.unhealthy, counts),
        'Unhealthy 2');
    expect(containerListChipLabel(ContainerListFilter.all, counts), 'All 5');
  });

  test('default landing is UNHEALTHY if any, else ALL', () {
    expect(defaultContainerListFilter(all), ContainerListFilter.unhealthy);
    expect(defaultContainerListFilter([plex, watchtower]),
        ContainerListFilter.all);
    expect(defaultContainerListFilter(const []), ContainerListFilter.all);
  });

  test('compose stacks group by project with STANDALONE last', () {
    final groups = groupContainersByCompose(all);
    expect(groups.map((g) => g.label), ['infra', 'media', 'STANDALONE']);
    expect(groups.last.rows.map((r) => r.names), ['watchtower', 'job']);
    expect(groups.first.rows.single.names, 'web');
  });

  test('kicker names engine and running/stopped counts', () {
    expect(
      containerListKicker(all),
      'DOCKER \u00b7 2 RUNNING \u00b7 3 STOPPED',
    );
    expect(
      containerListKicker([
        _row(names: 'db', engine: 'podman', state: 'exited', status: 'Exited'),
      ]),
      'PODMAN \u00b7 0 RUNNING \u00b7 1 STOPPED',
    );
  });

  test('meta is image and ports; restarting uses server status, no invented count',
      () {
    expect(containerListMeta(plex), 'linuxserver/plex \u00b7 32787\u219232400');
    expect(containerListMeta(transmission), contains('restarting'));
    expect(containerListMeta(transmission), isNot(contains('4 times in 5m')));
    expect(containerListMeta(watchtower), 'Exited (0) 3 days ago');
  });

  test('health: running healthy, restarting/unhealthy warning, exit codes', () {
    expect(containerHealth(plex), ContainerHealth.healthy);
    expect(containerHealth(transmission), ContainerHealth.warning);
    expect(containerHealth(unhealthy), ContainerHealth.warning);
    expect(containerHealth(crashed), ContainerHealth.failed);
    expect(containerHealth(watchtower), ContainerHealth.unknown);
  });
}
