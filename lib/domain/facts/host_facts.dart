import 'package:kelola/domain/facts/enums.dart';

enum SerialStatus { missing, available, requiresRoot }

class HostNic {
  const HostNic({
    required this.name,
    this.mac,
    this.ipv4,
    this.ipv6,
  });

  final String name;
  final String? mac;
  final String? ipv4;
  final String? ipv6;
}

class HostGpu {
  const HostGpu({
    this.model,
    this.vram,
    this.driver,
  });

  final String? model;
  final String? vram;
  final String? driver;
}

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
    this.model,
    this.virt,
    this.biosVendor,
    this.biosVersion,
    this.biosDate,
    this.serial,
    this.serialStatus = SerialStatus.missing,
    this.nics = const [],
    this.gpu,
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
  final String? model;
  final String? virt;
  final String? biosVendor;
  final String? biosVersion;
  final String? biosDate;
  final String? serial;
  final SerialStatus serialStatus;
  final List<HostNic> nics;
  final HostGpu? gpu;

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
