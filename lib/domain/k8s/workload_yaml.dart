import 'package:kelola/domain/k8s/workload.dart';

class YamlObjectId {
  const YamlObjectId({this.kind, this.name, this.namespace});

  final String? kind;
  final String? name;
  final String? namespace;
}

YamlObjectId parseYamlObjectId(String yaml) {
  String? kind;
  String? name;
  String? namespace;
  var inMetadata = false;
  for (final raw in yaml.split('\n')) {
    final line = raw.replaceAll('\t', '    ');
    final kindMatch = RegExp(r'^kind:\s*(\S+)').firstMatch(line);
    if (kindMatch != null) {
      kind = kindMatch.group(1);
    }
    if (RegExp(r'^metadata:\s*$').hasMatch(line)) {
      inMetadata = true;
      continue;
    }
    if (inMetadata && line.isNotEmpty && !line.startsWith(RegExp(r'\s'))) {
      inMetadata = false;
    }
    if (!inMetadata) {
      continue;
    }
    final nameMatch = RegExp(r'^\s+name:\s*(\S+)').firstMatch(line);
    if (nameMatch != null) {
      name = nameMatch.group(1);
    }
    final nsMatch = RegExp(r'^\s+namespace:\s*(\S+)').firstMatch(line);
    if (nsMatch != null) {
      namespace = nsMatch.group(1);
    }
  }
  return YamlObjectId(kind: kind, name: name, namespace: namespace);
}

void assertYamlMatchesWorkload(String yaml, K8sWorkload workload) {
  if (yaml.trim().isEmpty) {
    throw const FormatException('YAML is empty');
  }
  final id = parseYamlObjectId(yaml);
  if (id.kind != null && parseK8sKind(id.kind) != workload.kind) {
    throw FormatException('YAML kind does not match ${workload.kind.resource}');
  }
  if (id.name != null && id.name != workload.name) {
    throw FormatException('YAML name does not match ${workload.name}');
  }
  if (id.namespace != null && id.namespace != workload.namespace) {
    throw FormatException(
      'YAML namespace does not match ${workload.namespace}',
    );
  }
}
