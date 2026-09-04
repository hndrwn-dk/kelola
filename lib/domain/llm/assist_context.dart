class AssistContext {
  const AssistContext({
    this.unitNames = const [],
    this.paths = const [],
    this.hostAlias = '',
  });

  final List<String> unitNames;
  final List<String> paths;
  final String hostAlias;

  bool allowsUnit(String unit) => unitNames.contains(unit);

  bool allowsPath(String path) => paths.contains(path);
}
