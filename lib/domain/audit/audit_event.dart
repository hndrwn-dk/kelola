class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.timestampUtc,
    required this.hostId,
    required this.hostAlias,
    required this.remoteUser,
    required this.command,
    required this.risk,
    required this.usedSudo,
    required this.durationMs,
    required this.appVersion,
    this.title = '',
    this.exitCode,
    this.errorSummary,
  });

  final String id;
  final DateTime timestampUtc;
  final String hostId;
  final String hostAlias;
  final String remoteUser;
  final String title;
  final String command;
  final String risk;
  final bool usedSudo;
  final int durationMs;
  final String appVersion;
  final int? exitCode;
  final String? errorSummary;

  bool get orphan => exitCode == null && errorSummary == null;
}
