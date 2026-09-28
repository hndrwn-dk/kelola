import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

const kPtyTermType = 'xterm-256color';
const kPtyAuditCommand = 'ssh-pty';
const kPtyAuditOpen = 'Opened terminal';
const kPtyAuditClose = 'Closed terminal';

const kPtyMinCols = 20;
const kPtyMaxCols = 300;
const kPtyMinRows = 8;
const kPtyMaxRows = 120;

/// Default cell size for a first PTY request before [TerminalView] measures.
const kPtyCellWidth = 8.4;
const kPtyCellHeight = 17.0;

(int, int) clampPtySize(int cols, int rows) {
  return (
    cols.clamp(kPtyMinCols, kPtyMaxCols),
    rows.clamp(kPtyMinRows, kPtyMaxRows),
  );
}

(int, int) ptySizeFromView(double widthPx, double heightPx) {
  final cols = (widthPx / kPtyCellWidth).floor();
  final rows = (heightPx / kPtyCellHeight).floor();
  return clampPtySize(cols, rows);
}

String ptyCloseCommand(Duration elapsed) {
  return '$kPtyAuditCommand ${elapsed.inSeconds}s';
}

/// Marker probe for read-only refusal and audit titles. Never [execute]d.
class PtyBoundaryProbe extends Probe<void> {
  const PtyBoundaryProbe({this.closing = false});

  final bool closing;

  @override
  String command(HostFacts facts) =>
      closing ? ptyCloseCommand(Duration.zero) : kPtyAuditCommand;

  @override
  void parse(String stdout, String stderr, int exitCode) {
    throw UnsupportedError('PTY is not an exec probe');
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  String get auditTitle => closing ? kPtyAuditClose : kPtyAuditOpen;
}
