import 'package:kelola/domain/hosts/host.dart';

/// Exhaustive probe / connection outcome. Never infer "down" from cache age.
enum HostProbeOutcome {
  pending,
  awaitingVerification,
  awaitingAuth,
  unchecked,
  timedOut,
  refused,
  unreachable,
  healthy,
}

bool isConnectionFailureOutcome(HostProbeOutcome o) {
  return switch (o) {
    HostProbeOutcome.timedOut ||
    HostProbeOutcome.refused ||
    HostProbeOutcome.unreachable =>
      true,
    HostProbeOutcome.pending ||
    HostProbeOutcome.awaitingVerification ||
    HostProbeOutcome.awaitingAuth ||
    HostProbeOutcome.unchecked ||
    HostProbeOutcome.healthy =>
      false,
  };
}

/// Operator-facing state label. Never returns "down".
String hostProbeStateLabel(HostProbeOutcome outcome) {
  return switch (outcome) {
    HostProbeOutcome.pending => 'checking…',
    HostProbeOutcome.awaitingVerification => 'awaiting host key',
    HostProbeOutcome.awaitingAuth => 'awaiting unlock',
    HostProbeOutcome.unchecked => 'not checked',
    HostProbeOutcome.timedOut => 'unreachable',
    HostProbeOutcome.refused => 'unreachable',
    HostProbeOutcome.unreachable => 'unreachable',
    HostProbeOutcome.healthy => 'ok',
  };
}

/// Classify a thrown error after a probe was attempted.
HostProbeOutcome classifyProbeFailure(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('timed out') || s.contains('timeout')) {
    return HostProbeOutcome.timedOut;
  }
  if (s.contains('connection refused') || s.contains('refused')) {
    return HostProbeOutcome.refused;
  }
  if (s.contains('auth_failed') ||
      s.contains('auth') &&
          (s.contains('cancel') || s.contains('user canceled') || s.contains('user cancelled'))) {
    return HostProbeOutcome.unchecked;
  }
  if (s.contains('host key') || s.contains('hostkey')) {
    return HostProbeOutcome.awaitingVerification;
  }
  return HostProbeOutcome.unreachable;
}

String fleetUnreachableMessage({
  required HostProbeOutcome outcome,
  required bool hasCache,
  DateTime? fetchedAt,
  DateTime? now,
}) {
  final state = hostProbeStateLabel(outcome);
  if (!isConnectionFailureOutcome(outcome)) {
    return state;
  }
  if (hasCache && fetchedAt != null) {
    return '$state · cache ${Host.ageLabel(fetchedAt, now: now)}';
  }
  return state;
}
