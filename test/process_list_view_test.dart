import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/processes/process_list_view.dart';

ProcessRow _p({
  required String command,
  int pid = 10,
  double cpu = 1,
  int rssKb = 1024,
  String etime = '00:02:00',
  String user = 'hendra',
}) {
  return ProcessRow(
    pid: pid,
    ppid: 1,
    user: user,
    cpu: cpu,
    mem: 0,
    rssKb: rssKb,
    etime: etime,
    stat: 'S',
    command: command,
  );
}

void main() {
  test('sorts by cpu, memory, then name', () {
    final rows = [
      _p(command: 'sshd', cpu: 1, rssKb: 12 * 1024),
      _p(command: 'ffmpeg', cpu: 187, rssKb: 2100 * 1024),
      _p(command: 'mysqld', cpu: 21, rssKb: 1400 * 1024),
    ];
    expect(
      sortProcesses(rows, ProcessSort.cpu).map((p) => p.command),
      ['ffmpeg', 'mysqld', 'sshd'],
    );
    expect(
      sortProcesses(rows, ProcessSort.memory).first.command,
      'ffmpeg',
    );
    expect(
      sortProcesses(rows, ProcessSort.name).map((p) => p.command),
      ['ffmpeg', 'mysqld', 'sshd'],
    );
  });

  test('formats rss and etime like S12', () {
    expect(formatProcessRss(2100 * 1024), '2.1 GB');
    expect(formatProcessRss(412 * 1024), '412 MB');
    expect(formatProcessEtime('04:12:00'), '4h12m');
    expect(formatProcessEtime('47-00:00:00'), '47d');
    expect(formatProcessEtime('00:02:00'), '2m');
  });

  test('meta is pid · user · age', () {
    expect(
      processListMeta(_p(command: 'ffmpeg', pid: 41203, user: 'plex', etime: '04:12:00')),
      'pid 41203 · plex · 4h12m',
    );
  });
}
