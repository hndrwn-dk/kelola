import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/risk/risk_level.dart';

AuditEvent ev({
  String id = '1',
  DateTime? ts,
  String title = '',
  String command = 'echo hi',
  String risk = 'read',
  int? exitCode = 0,
  String? errorSummary,
  bool usedSudo = false,
  int durationMs = 100,
}) {
  return AuditEvent(
    id: id,
    timestampUtc: ts ?? DateTime.utc(2026, 9, 2, 10),
    hostId: 'h',
    hostAlias: 'nas-01',
    remoteUser: 'hendra',
    title: title,
    command: command,
    risk: risk,
    usedSudo: usedSudo,
    durationMs: durationMs,
    appVersion: '0.1.0',
    exitCode: exitCode,
    errorSummary: errorSummary,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 2, 17);

  test('default filter keeps mutate and destructive, hides successful reads', () {
    final rows = [
      ev(id: 'r', title: 'Polled dashboard', risk: 'read'),
      ev(id: 'm', title: 'Restarted nginx.service', risk: 'mutate'),
      ev(id: 'd', title: 'Rebooted host', risk: 'destructive'),
    ];
    final shown = filterAudit(rows, showAll: false);
    expect(shown.map((e) => e.id), ['m', 'd']);
    expect(filterAudit(rows, showAll: true).map((e) => e.id), ['r', 'm', 'd']);
  });

  test('failed reads still appear in the default view', () {
    final rows = [
      ev(id: 'ok', title: 'Polled dashboard', risk: 'read'),
      ev(
        id: 'fail',
        title: 'Polled dashboard',
        risk: 'read',
        exitCode: 1,
      ),
      ev(
        id: 'ro',
        title: 'Restarted nginx.service',
        risk: 'mutate',
        exitCode: null,
        errorSummary: 'ReadOnlyViolation',
      ),
      ev(
        id: 'hk',
        title: 'Host key mismatch',
        command: 'host-key-verify',
        risk: 'read',
        exitCode: 1,
        errorSummary: 'host key mismatch SHA256:other',
      ),
    ];
    final shown = filterAudit(rows, showAll: false);
    expect(shown.map((e) => e.id), ['fail', 'ro', 'hk']);
  });

  test('seven-day summary counts changes, destructive, and failed', () {
    final rows = [
      ev(
        id: 'old',
        ts: DateTime.utc(2026, 8, 20),
        title: 'Restarted nginx.service',
        risk: 'mutate',
      ),
      ev(id: 'm', title: 'Restarted nginx.service', risk: 'mutate'),
      ev(id: 'd', title: 'Rebooted host', risk: 'destructive'),
      ev(
        id: 'fail',
        title: 'Polled dashboard',
        risk: 'read',
        exitCode: 1,
      ),
      ev(id: 'read', title: 'Read journal', risk: 'read'),
    ];
    final summary = summarizeAudit(rows, now: now);
    expect(summary.changes, 2);
    expect(summary.destructive, 1);
    expect(summary.failed, 1);
    expect(
      formatAuditWeekSummary(summary),
      'Last 7 days · 2 changes · 1 destructive · 1 failed',
    );
  });

  test('groups records by UTC day with Today and Yesterday labels', () {
    final rows = [
      ev(id: 't', ts: DateTime.utc(2026, 9, 2, 9), title: 'Restarted nginx.service', risk: 'mutate'),
      ev(id: 'y', ts: DateTime.utc(2026, 9, 1, 18), title: 'Stopped cron.service', risk: 'mutate'),
      ev(id: 'o', ts: DateTime.utc(2026, 8, 30, 12), title: 'Rebooted host', risk: 'destructive'),
    ];
    final groups = groupAuditByDay(rows, now: now);
    expect(groups.map((g) => g.label), ['Today', 'Yesterday', '30 Aug 2026']);
    expect(groups[0].events.map((e) => e.id), ['t']);
    expect(groups[1].events.map((e) => e.id), ['y']);
    expect(groups[2].events.map((e) => e.id), ['o']);
  });

  test('failed records are flagged for non-zero exit, ReadOnlyViolation, host key mismatch', () {
    expect(auditFailed(ev(exitCode: 0)), isFalse);
    expect(auditFailed(ev(exitCode: 1)), isTrue);
    expect(
      auditFailed(ev(exitCode: null, errorSummary: 'ReadOnlyViolation')),
      isTrue,
    );
    expect(
      auditFailed(
        ev(
          command: 'host-key-verify',
          exitCode: 1,
          errorSummary: 'host key mismatch SHA256:x',
        ),
      ),
      isTrue,
    );
    expect(auditFailed(ev(exitCode: null, errorSummary: null)), isFalse);
    expect(auditRisk('destructive'), RiskLevel.destructive);
    expect(auditRisk('read'), RiskLevel.read);
  });

  test('display title never uses LC_ALL=C, even for legacy rows', () {
    expect(
      auditDisplayTitle(ev(title: 'Restarted nginx.service', command: 'LC_ALL=C')),
      'Restarted nginx.service',
    );
    expect(
      auditDisplayTitle(ev(title: '', command: 'LC_ALL=C')),
      isNot(contains('LC_ALL')),
    );
    expect(
      auditDisplayTitle(ev(title: 'LC_ALL=C', command: 'LC_ALL=C\necho hi')),
      isNot(equals('LC_ALL=C')),
    );
    expect(
      auditDisplayTitle(
        ev(title: '', command: 'host-key-verify', errorSummary: 'host key mismatch x'),
      ),
      'Host key mismatch',
    );
  });

  test('export JSON includes every record and keeps raw command', () {
    final rows = [
      ev(id: 'r', title: 'Polled dashboard', command: 'LC_ALL=C\ncat /proc/uptime', risk: 'read'),
      ev(id: 'm', title: 'Restarted nginx.service', command: 'sudo -n systemctl restart nginx.service', risk: 'mutate'),
    ];
    final json = encodeAuditExport(rows);
    expect(json, contains('Polled dashboard'));
    expect(json, contains('Restarted nginx.service'));
    expect(json, contains('LC_ALL=C'));
    expect(json, contains('sudo -n systemctl restart nginx.service'));
  });
}
