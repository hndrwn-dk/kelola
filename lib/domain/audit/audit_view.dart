import 'dart:convert';

import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class AuditDraft {
  const AuditDraft({
    required this.title,
    required this.command,
    required this.risk,
    required this.usedSudo,
  });

  final String title;
  final String command;
  final String risk;
  final bool usedSudo;

  factory AuditDraft.fromProbe(Probe<dynamic> probe, HostFacts facts) {
    return AuditDraft(
      title: probe.auditTitle,
      command: probe.command(facts),
      risk: probe.risk.name,
      usedSudo: probe.needsSudo,
    );
  }
}

class AuditWeekSummary {
  const AuditWeekSummary({
    required this.changes,
    required this.destructive,
    required this.failed,
  });

  final int changes;
  final int destructive;
  final int failed;
}

class AuditDayGroup {
  const AuditDayGroup({
    required this.day,
    required this.label,
    required this.events,
  });

  final DateTime day;
  final String label;
  final List<AuditEvent> events;
}

bool auditFailed(AuditEvent e) {
  if (e.exitCode != null && e.exitCode != 0) {
    return true;
  }
  final err = e.errorSummary;
  return err != null && err.isNotEmpty;
}

bool auditIsChange(AuditEvent e) {
  return e.risk == RiskLevel.mutate.name ||
      e.risk == RiskLevel.destructive.name;
}

bool auditVisibleByDefault(AuditEvent e) {
  return auditIsChange(e) || auditFailed(e);
}

RiskLevel auditRisk(String risk) {
  return switch (risk) {
    'mutate' => RiskLevel.mutate,
    'destructive' => RiskLevel.destructive,
    _ => RiskLevel.read,
  };
}

List<AuditEvent> filterAudit(
  List<AuditEvent> rows, {
  required bool showAll,
}) {
  if (showAll) {
    return List<AuditEvent>.of(rows);
  }
  return rows.where(auditVisibleByDefault).toList();
}

AuditWeekSummary summarizeAudit(
  List<AuditEvent> rows, {
  required DateTime now,
}) {
  final cutoff = now.toUtc().subtract(const Duration(days: 7));
  var changes = 0;
  var destructive = 0;
  var failed = 0;
  for (final e in rows) {
    if (e.timestampUtc.isBefore(cutoff)) {
      continue;
    }
    if (auditIsChange(e)) {
      changes++;
    }
    if (e.risk == RiskLevel.destructive.name) {
      destructive++;
    }
    if (auditFailed(e)) {
      failed++;
    }
  }
  return AuditWeekSummary(
    changes: changes,
    destructive: destructive,
    failed: failed,
  );
}

String formatAuditWeekSummary(AuditWeekSummary summary) {
  return 'Last 7 days · ${summary.changes} changes · '
      '${summary.destructive} destructive · ${summary.failed} failed';
}

enum AuditInsightKind { empty, changes, alert }

AuditInsightKind auditInsightKind(AuditWeekSummary summary) {
  if (summary.changes == 0 &&
      summary.destructive == 0 &&
      summary.failed == 0) {
    return AuditInsightKind.empty;
  }
  if (summary.failed > 0 || summary.destructive > 0) {
    return AuditInsightKind.alert;
  }
  return AuditInsightKind.changes;
}

String formatAuditInsight(AuditWeekSummary summary) {
  return '7 days · ${summary.changes} changes · '
      '${summary.destructive} destructive · ${summary.failed} failed';
}

List<AuditDayGroup> groupAuditByDay(
  List<AuditEvent> rows, {
  required DateTime now,
}) {
  final map = <DateTime, List<AuditEvent>>{};
  final order = <DateTime>[];
  for (final e in rows) {
    final day = _utcDay(e.timestampUtc);
    final bucket = map.putIfAbsent(day, () {
      order.add(day);
      return <AuditEvent>[];
    });
    bucket.add(e);
  }
  return [
    for (final day in order)
      AuditDayGroup(
        day: day,
        label: _dayLabel(day, now),
        events: map[day]!,
      ),
  ];
}

String auditDisplayTitle(AuditEvent e) {
  final t = e.title.trim();
  if (t.isNotEmpty && !_looksLikeLocalePrefix(t)) {
    return t;
  }
  if (_isHostKeyRecord(e)) {
    return 'Host key mismatch';
  }
  if (_looksLikeLocalePrefix(t) || _looksLikeLocalePrefix(e.command)) {
    return 'Read probe';
  }
  if (t.isNotEmpty) {
    return t;
  }
  return 'Recorded action';
}

String auditScreenTitle(String? hostLabel) {
  final label = hostLabel?.trim();
  if (label == null || label.isEmpty) {
    return 'Audit · All hosts';
  }
  return 'Audit · $label';
}

Map<String, Object?> auditExportRow(AuditEvent e) {
  return {
    'id': e.id,
    'ts': e.timestampUtc.toIso8601String(),
    'host': e.hostAlias,
    'user': e.remoteUser,
    'title': e.title,
    'command': e.command,
    'risk': e.risk,
    'sudo': e.usedSudo,
    'exit': e.exitCode,
    'ms': e.durationMs,
    'error': e.errorSummary,
  };
}

String encodeAuditExport(List<AuditEvent> rows) {
  return jsonEncode(rows.map(auditExportRow).toList());
}

bool _looksLikeLocalePrefix(String s) {
  final t = s.trim();
  return t == 'LC_ALL=C' || t.startsWith('LC_ALL=');
}

bool _isHostKeyRecord(AuditEvent e) {
  if (e.command.trim() == 'host-key-verify') {
    return true;
  }
  return (e.errorSummary ?? '').toLowerCase().contains('host key mismatch');
}

DateTime _utcDay(DateTime ts) {
  final u = ts.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

String _dayLabel(DateTime day, DateTime now) {
  final today = _utcDay(now);
  final diff = today.difference(day).inDays;
  if (diff == 0) {
    return 'Today';
  }
  if (diff == 1) {
    return 'Yesterday';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${day.day} ${months[day.month - 1]} ${day.year}';
}
