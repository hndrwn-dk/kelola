import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum EnvScope { host, tag }

class EnvBinding {
  const EnvBinding({
    required this.id,
    required this.scope,
    required this.scopeId,
    required this.name,
    required this.value,
  });

  final String id;
  final EnvScope scope;
  final String scopeId;
  final String name;
  final String value;
}

final _envName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

bool isEnvName(String name) => _envName.hasMatch(name);

Map<String, String> resolveHostEnv(Host host, List<EnvBinding> all) {
  final resolved = <String, String>{};
  final tags = [...host.tags]..sort();
  for (final tag in tags) {
    for (final binding in all) {
      if (binding.scope == EnvScope.tag &&
          binding.scopeId == tag &&
          isEnvName(binding.name)) {
        resolved[binding.name] = binding.value;
      }
    }
  }
  for (final binding in all) {
    if (binding.scope == EnvScope.host &&
        binding.scopeId == host.id &&
        isEnvName(binding.name)) {
      resolved[binding.name] = binding.value;
    }
  }
  return resolved;
}

String prefixEnvExports(String command, Map<String, String> env) {
  final exports = [
    for (final entry in env.entries)
      if (isEnvName(entry.key))
        'export ${entry.key}=${shellSingleQuote(entry.value)}; ',
  ];
  if (exports.isEmpty) {
    return command;
  }
  return '${exports.join()}$command';
}
