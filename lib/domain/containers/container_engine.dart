String containerEngineBin(String engine) {
  return engine == 'podman' ? 'podman' : 'docker';
}

/// Run [args] on docker or podman. Non-sudo first (rootless / docker group),
/// then `sudo -n`.
String containerEngineCommand({
  required String engine,
  required String args,
}) {
  final bin = containerEngineBin(engine);
  return '''
LC_ALL=C
bin=\$(command -v $bin || true)
if [ -z "\$bin" ]; then echo missing engine; exit 1; fi
"\$bin" $args 2>/dev/null || sudo -n "\$bin" $args
''';
}

String containerEngineScript({
  required String engine,
  required String body,
}) {
  final bin = containerEngineBin(engine);
  return '''
LC_ALL=C
bin=\$(command -v $bin || true)
if [ -z "\$bin" ]; then echo missing engine; exit 1; fi
run() { "\$bin" "\$@" 2>/dev/null || sudo -n "\$bin" "\$@"; }
$body
''';
}
