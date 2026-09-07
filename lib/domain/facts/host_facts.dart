import 'package:kelola/domain/facts/enums.dart';

enum SerialStatus { missing, available, requiresRoot }

/// How Kelola may read journald / syslog on this host.
///
/// Privileged (`sudo -n`) legs run at most once while [unknown]. The outcome
/// is cached so Logs / follow never spam auth.log on every open.
enum JournalAccess {
  /// Not yet learned (or only HostFacts plain probe ran and failed).
  unknown,

  /// Unprivileged read works — never escalate.
  plain,

  /// Plain failed; passwordless sudo works — sudo only.
  sudo,

  /// Plain and sudo both failed once — never retry sudo automatically.
  denied,
}

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
    this.journalAccess = JournalAccess.unknown,
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
  final JournalAccess journalAccess;
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

  /// [journalReadable] from HostFactsProbe implies plain without a sudo try.
  JournalAccess get effectiveJournalAccess {
    if (journalAccess != JournalAccess.unknown) {
      return journalAccess;
    }
    if (journalReadable) {
      return JournalAccess.plain;
    }
    return JournalAccess.unknown;
  }

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

  HostFacts copyWith({
    String? osId,
    String? osVersionId,
    InitSystem? init,
    int? systemdVersion,
    PackageManager? pkg,
    FirewallBackend? fw,
    bool? hasJournald,
    bool? journalReadable,
    JournalAccess? journalAccess,
    String? arch,
    String? prettyName,
    List<String>? runtimes,
    int? nprocCores,
    String? model,
    String? virt,
    String? biosVendor,
    String? biosVersion,
    String? biosDate,
    String? serial,
    SerialStatus? serialStatus,
    List<HostNic>? nics,
    HostGpu? gpu,
  }) {
    return HostFacts(
      osId: osId ?? this.osId,
      osVersionId: osVersionId ?? this.osVersionId,
      init: init ?? this.init,
      systemdVersion: systemdVersion ?? this.systemdVersion,
      pkg: pkg ?? this.pkg,
      fw: fw ?? this.fw,
      hasJournald: hasJournald ?? this.hasJournald,
      journalReadable: journalReadable ?? this.journalReadable,
      journalAccess: journalAccess ?? this.journalAccess,
      arch: arch ?? this.arch,
      prettyName: prettyName ?? this.prettyName,
      runtimes: runtimes ?? this.runtimes,
      nprocCores: nprocCores ?? this.nprocCores,
      model: model ?? this.model,
      virt: virt ?? this.virt,
      biosVendor: biosVendor ?? this.biosVendor,
      biosVersion: biosVersion ?? this.biosVersion,
      biosDate: biosDate ?? this.biosDate,
      serial: serial ?? this.serial,
      serialStatus: serialStatus ?? this.serialStatus,
      nics: nics ?? this.nics,
      gpu: gpu ?? this.gpu,
    );
  }

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

/// Keep a learned sudo/denied verdict across HostFactsProbe rediscovery.
HostFacts coalesceJournalAccess(HostFacts incoming, HostFacts? previous) {
  if (incoming.journalAccess == JournalAccess.plain ||
      incoming.journalAccess == JournalAccess.sudo ||
      incoming.journalAccess == JournalAccess.denied) {
    return incoming.copyWith(
      journalReadable: incoming.journalAccess == JournalAccess.plain ||
          incoming.journalAccess == JournalAccess.sudo,
    );
  }
  if (previous != null &&
      (previous.journalAccess == JournalAccess.sudo ||
          previous.journalAccess == JournalAccess.denied)) {
    return incoming.copyWith(
      journalAccess: previous.journalAccess,
      journalReadable: previous.journalAccess == JournalAccess.sudo,
    );
  }
  if (incoming.journalReadable) {
    return incoming.copyWith(journalAccess: JournalAccess.plain);
  }
  return incoming;
}
