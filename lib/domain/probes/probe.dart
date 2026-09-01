import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// Typed command sent over SSH. No raw shell strings in the UI layer.
abstract class Probe<T> {
  const Probe();

  String command(HostFacts facts);

  T parse(String stdout, String stderr, int exitCode);

  bool get needsSudo;

  RiskLevel get risk;

  Duration get timeout => const Duration(seconds: 20);
}

class ProbeExecResult {
  const ProbeExecResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;
}

class ReadOnlyViolation implements Exception {
  ReadOnlyViolation(this.probe);

  final Probe<dynamic> probe;

  @override
  String toString() =>
      'Read-only host refused ${probe.runtimeType} (${probe.risk.name})';
}
