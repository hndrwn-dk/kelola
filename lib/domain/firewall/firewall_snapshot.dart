import 'package:kelola/domain/facts/enums.dart';

class FirewallRule {
  const FirewallRule({
    required this.id,
    required this.summary,
    this.port,
    this.service,
    this.action,
    this.zone,
    this.chain,
    this.handle,
  });

  final String id;
  final String summary;
  final String? port;
  final String? service;
  final String? action;
  final String? zone;
  final String? chain;
  final String? handle;

  int? get portNumber {
    final p = port;
    if (p == null || p.isEmpty) {
      return null;
    }
    final n = int.tryParse(p.split('/').first);
    return n;
  }
}

class FirewallSnapshot {
  const FirewallSnapshot({
    required this.backend,
    required this.rules,
    this.defaultPolicy,
    this.defaultZone,
    this.readOnly = false,
  });

  final FirewallBackend backend;
  final List<FirewallRule> rules;
  final String? defaultPolicy;
  final String? defaultZone;
  final bool readOnly;
}

enum FirewallVerb { addPort, removePort }

class FirewallChange {
  const FirewallChange({
    required this.verb,
    required this.port,
    this.zone,
    this.handle,
    this.chain,
    this.revertPid,
  });

  final FirewallVerb verb;
  final String port;
  final String? zone;
  final String? handle;
  final String? chain;
  final int? revertPid;

  String get label => port;

  FirewallChange copyWith({
    int? revertPid,
    String? handle,
  }) {
    return FirewallChange(
      verb: verb,
      port: port,
      zone: zone,
      handle: handle ?? this.handle,
      chain: chain,
      revertPid: revertPid ?? this.revertPid,
    );
  }
}

class FirewallApplyResult {
  const FirewallApplyResult({
    required this.change,
    this.revertPid,
    this.handle,
  });

  final FirewallChange change;
  final int? revertPid;
  final String? handle;
}
