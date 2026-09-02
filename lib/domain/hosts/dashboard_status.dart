import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/sudo_hint.dart';

export 'package:kelola/domain/sudo_hint.dart' show sudoMutateWillFail;

/// One dashboard footer line: freshness first, then host-mode warnings.
String dashboardStatusLine({
  DateTime? checkedAt,
  bool readOnly = false,
  bool sudoNeedsPassword = false,
  DateTime? now,
}) {
  final parts = <String>[];
  if (checkedAt != null) {
    parts.add('Checked ${Host.ageLabel(checkedAt, now: now)}');
  }
  if (readOnly) {
    parts.add('read-only');
  }
  if (sudoNeedsPassword) {
    parts.add(sudoMutateWillFail);
  }
  return parts.join(' · ');
}
