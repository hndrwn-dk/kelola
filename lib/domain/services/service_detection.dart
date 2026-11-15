import 'package:kelola/domain/services/container_services.dart';
import 'package:kelola/domain/services/service_catalog.dart';

/// `installed` = binary found, no unit seen.
enum ServiceState { running, stopped, failed, installed }

class DetectedService {
  const DetectedService({
    required this.id,
    required this.state,
    this.unit,
    this.version,
    this.binaries = const {},
    this.container,
    this.image,
  });

  final ServiceId id;
  final ServiceState state;

  /// M52c: the Docker container that runs it (its name, validated by
  /// `isSafeContainerName`); null for a host service.
  final String? container;

  /// M52c: the container's image as `docker ps` printed it; display only.
  final String? image;

  bool get inContainer => container != null;

  /// `nginx.service` / `nginx`.
  final String? unit;

  /// `1.24.0`.
  final String? version;

  /// Binary name to absolute path.
  final Map<String, String> binaries;

  Map<String, dynamic> toJson() => {
    'id': id.name,
    'state': state.name,
    if (unit != null) 'unit': unit,
    if (version != null) 'version': version,
    if (binaries.isNotEmpty) 'bin': binaries,
    if (container != null) 'ctr': container,
    if (image != null) 'img': image,
  };

  /// Null when the id or state is unknown (e.g. written by a newer app).
  static DetectedService? fromJson(Object? j) {
    if (j is! Map) {
      return null;
    }
    final id = _byName(ServiceId.values, j['id']);
    final state = _byName(ServiceState.values, j['state']);
    if (id == null || state == null) {
      return null;
    }
    final bin = j['bin'];
    final ctr = j['ctr'];
    // A cached name is re-checked: the cache is a file on the phone, and the
    // name reaches a docker command.
    if (ctr != null && (ctr is! String || !isSafeContainerName(ctr))) {
      return null;
    }
    return DetectedService(
      id: id,
      state: state,
      unit: j['unit'] is String ? j['unit'] as String : null,
      version: j['version'] is String ? j['version'] as String : null,
      binaries: {
        if (bin is Map)
          for (final e in bin.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      container: ctr as String?,
      image: j['img'] is String ? j['img'] as String : null,
    );
  }
}

/// What a host runs, as last read by the service detect probe.
class ServiceDetection {
  const ServiceDetection({
    required this.services,
    required this.listeningPorts,
    required this.readAt,
    this.containersSkipped = false,
  });

  final List<DetectedService> services;

  /// M52c: plain `docker` failed and sudo was not tried (an automatic read),
  /// so the container list is unknown, not empty. Not persisted.
  final bool containersSkipped;

  /// This read, keeping [previous]'s container services when this read
  /// skipped them.
  ServiceDetection keepingContainersOf(ServiceDetection? previous) {
    if (!containersSkipped || previous == null) return this;
    return ServiceDetection(
      services: [
        ...services,
        for (final s in previous.services)
          if (s.inContainer) s,
      ],
      listeningPorts: listeningPorts,
      readAt: readAt,
      containersSkipped: true,
    );
  }

  /// "Listening on this host"; not attributed to a service.
  final List<int> listeningPorts;
  final DateTime readAt;

  Map<String, dynamic> toJson() => {
    'at': readAt.toUtc().toIso8601String(),
    'services': [for (final s in services) s.toJson()],
    'ports': listeningPorts,
  };

  /// Null for anything that is not a usable record. Junk entries inside the
  /// lists are skipped; they do not discard the record.
  static ServiceDetection? fromJson(Object? j) {
    if (j is! Map) {
      return null;
    }
    final at = DateTime.tryParse(j['at'] is String ? j['at'] as String : '');
    final services = j['services'];
    if (at == null || services is! List) {
      return null;
    }
    final ports = j['ports'];
    return ServiceDetection(
      services: [
        for (final s in services)
          ?DetectedService.fromJson(s),
      ],
      listeningPorts: [
        if (ports is List)
          for (final p in ports)
            if (p is int) p,
      ],
      readAt: at,
    );
  }
}

T? _byName<T extends Enum>(List<T> values, Object? raw) {
  for (final v in values) {
    if (v.name == raw) {
      return v;
    }
  }
  return null;
}
