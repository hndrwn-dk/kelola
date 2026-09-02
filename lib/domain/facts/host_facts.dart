import 'package:kelola/domain/facts/enums.dart';

class HostFacts {
  const HostFacts({
    required this.osId,
    required this.osVersionId,
    required this.init,
    required this.systemdVersion,
    required this.pkg,
    required this.fw,
    required this.hasJournald,
    required this.journalReadable,
    required this.arch,
    this.prettyName,
    this.runtimes = const [],
    this.nprocCores,
  });

  final String osId;
  final String osVersionId;
  final InitSystem init;
  final int? systemdVersion;
  final PackageManager pkg;
  final FirewallBackend fw;
  final bool hasJournald;
  final bool journalReadable;
  final String arch;
  final String? prettyName;
  final List<String> runtimes;
  final int? nprocCores;

  static const undiscovered = HostFacts(
    osId: '',
    osVersionId: '',
    init: InitSystem.unknown,
    systemdVersion: null,
    pkg: PackageManager.unknown,
    fw: FirewallBackend.none,
    hasJournald: false,
    journalReadable: false,
    arch: '',
  );

  String get label {
    if (prettyName != null && prettyName!.isNotEmpty) {
      return prettyName!;
    }
    if (osId.isEmpty) {
      return 'unknown';
    }
    return osVersionId.isEmpty ? osId : '$osId $osVersionId';
  }

  bool get hasK8s =>
      runtimes.contains('k3s') || runtimes.contains('kubectl');

  bool get hasContainers =>
      hasK8s ||
      runtimes.contains('docker') ||
      runtimes.contains('podman') ||
      runtimes.contains('crictl') ||
      runtimes.contains('nerdctl');
}
