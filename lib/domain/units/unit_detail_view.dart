import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';

String unitDetailKicker(UnitDetail detail, {DateTime? now}) {
  return unitDetailMeta(detail, now: now).toUpperCase();
}

String unitDetailMeta(UnitDetail detail, {DateTime? now}) {
  if (detail.activeState == 'failed') {
    final cause = unitFailureCause(detail);
    return cause == null ? 'failed' : 'failed · $cause';
  }
  if (detail.activeState == 'active') {
    final up = unitUptimeLabel(detail, now: now);
    return up == null ? 'active' : 'active · $up';
  }
  final bits = <String>[
    if (detail.activeState.isNotEmpty) detail.activeState,
    if (detail.subState.isNotEmpty && detail.subState != detail.activeState)
      detail.subState,
  ];
  return bits.join(' · ');
}

/// Exit / result fragment only. Null when there is nothing useful to add.
String? unitFailureCause(UnitDetail detail) {
  final status = int.tryParse(detail.execMainStatus);
  final code = int.tryParse(detail.execMainCode);
  final result = detail.result.trim();
  final unhelpfulStatus = status == null || status == 0;

  final named = result == 'signal' ||
      result == 'core-dump' ||
      result == 'oom-kill' ||
      result == 'timeout' ||
      result == 'watchdog' ||
      code == 2 ||
      code == 3;
  if (named) {
    final kind = result.isNotEmpty && result != 'success'
        ? result
        : (code == 3 ? 'core-dump' : 'signal');
    if (!unhelpfulStatus && (kind == 'signal' || kind == 'core-dump')) {
      return '$kind $status';
    }
    return kind;
  }

  if (!unhelpfulStatus) {
    return 'exit $status';
  }
  if (result.isNotEmpty && result != 'success') {
    return result;
  }
  return null;
}

String? unitUptimeLabel(UnitDetail detail, {DateTime? now}) {
  if (detail.activeState != 'active') {
    return null;
  }
  final at = parseActiveEnterTimestamp(detail);
  if (at == null) {
    return null;
  }
  return _age(at, now: now);
}

DateTime? parseActiveEnterTimestamp(UnitDetail detail) {
  final usec = int.tryParse(detail.activeEnterTimestampUSec);
  if (usec != null && usec > 0) {
    return DateTime.fromMicrosecondsSinceEpoch(usec, isUtc: true);
  }
  final raw = detail.activeEnterTimestamp.trim();
  if (raw.isEmpty || raw.toLowerCase() == 'n/a') {
    return null;
  }
  final m = RegExp(r'(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})').firstMatch(raw);
  if (m == null) {
    return null;
  }
  return DateTime.tryParse('${m.group(1)}T${m.group(2)}Z');
}

String unitResultBody(UnitDetail detail) {
  final logs = detail.logs.trim();
  if (logs.isNotEmpty) {
    final lines = logs.split('\n').where((l) => l.trim().isNotEmpty).take(6);
    return lines.join('\n');
  }
  return unitFailureCause(detail) ?? detail.result;
}

RiskLevel unitActionRisk(UnitVerb verb, String unit) {
  return isDestructiveUnitAction(verb, unit)
      ? RiskLevel.destructive
      : RiskLevel.mutate;
}

String unitActionMeta(UnitVerb verb, String unit) {
  if (isDestructiveUnitAction(verb, unit)) {
    return 'destructive · will end this session';
  }
  return switch (verb) {
    UnitVerb.disable => "mutate · won't start at boot",
    UnitVerb.enable => 'mutate · start at boot',
    _ => 'mutate · one confirmation',
  };
}

String _age(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
  if (d.inMinutes < 1) {
    return 'just now';
  }
  if (d.inHours < 1) {
    return '${d.inMinutes}m';
  }
  if (d.inDays < 1) {
    return '${d.inHours}h';
  }
  return '${d.inDays}d';
}
