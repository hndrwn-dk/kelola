enum UnitVerb {
  start,
  stop,
  restart,
  reload,
  enable,
  disable,
}

class ServiceUnit {
  const ServiceUnit({
    required this.name,
    required this.description,
    required this.load,
    required this.active,
    required this.sub,
    this.unitFileState,
  });

  final String name;
  final String description;
  final String load;
  final String active;
  final String sub;
  final String? unitFileState;

  bool get isFailed => active == 'failed' || sub == 'failed';

  bool get isActive => active == 'active';
}

class UnitListResult {
  const UnitListResult({
    required this.units,
    required this.initSupported,
  });

  final List<ServiceUnit> units;
  final bool initSupported;

  List<ServiceUnit> get failed => units.where((u) => u.isFailed).toList();
}

class UnitDetail {
  const UnitDetail({
    required this.name,
    required this.properties,
    required this.logs,
    required this.dependencies,
  });

  final String name;
  final Map<String, String> properties;
  final String logs;
  final String dependencies;

  String get description => properties['Description'] ?? '';
  String get activeState => properties['ActiveState'] ?? '';
  String get subState => properties['SubState'] ?? '';
  String get unitFileState => properties['UnitFileState'] ?? '';
  String get fragmentPath => properties['FragmentPath'] ?? '';
  String get result => properties['Result'] ?? '';
  String get mainPid => properties['MainPID'] ?? '';
  String get execMainStatus => properties['ExecMainStatus'] ?? '';
  String get execMainCode => properties['ExecMainCode'] ?? '';
  String get activeEnterTimestamp => properties['ActiveEnterTimestamp'] ?? '';
  String get activeEnterTimestampUSec =>
      properties['ActiveEnterTimestampUSec'] ?? '';
}

class UnitActionResult {
  const UnitActionResult({
    required this.verb,
    required this.unit,
    required this.exitCode,
    required this.stderr,
    this.activeState = '',
    this.subState = '',
    this.mainPid = '',
    this.result = '',
  });

  final UnitVerb verb;
  final String unit;
  final int exitCode;
  final String stderr;
  final String activeState;
  final String subState;
  final String mainPid;
  final String result;

  bool get ok => exitCode == 0;

  bool get isActive => activeState == 'active';

  bool get mismatch {
    if (!ok) {
      return false;
    }
    switch (verb) {
      case UnitVerb.stop:
      case UnitVerb.disable:
        return isActive;
      case UnitVerb.start:
      case UnitVerb.restart:
        return activeState.isNotEmpty && !isActive && activeState != 'activating';
      default:
        return false;
    }
  }
}
