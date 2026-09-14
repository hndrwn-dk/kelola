String containerEngineBin(String engine) {
  return engine == 'podman' ? 'podman' : 'docker';
}

/// Exec channels are not login shells, so PAM never sets this. Rootless
/// Podman then misses containers the same user can see in a terminal.
const podmanUserSession = r'''
uid=$(id -u)
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$uid" ]; then
  export XDG_RUNTIME_DIR="/run/user/$uid"
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
''';

/// Rootful Podman is not on the user store. Group membership only opens
/// `/run/podman/podman.sock`; the client still has to talk to that URL.
/// Tries the socket only when this user can read it, then falls through.
const podmanSocketCommand = r'''{ sock=/run/podman/podman.sock; [ -S "$sock" ] && [ -r "$sock" ] && "$bin" --remote --url "unix://$sock" ''';

String _podmanSocketOrEmpty(String engine, String tail) {
  if (engine != 'podman') return '';
  return '$podmanSocketCommand$tail; } || ';
}

/// Run [args] on docker or podman. Non-sudo first (rootless / docker group /
/// readable podman socket), then `sudo -n`.
String containerEngineCommand({
  required String engine,
  required String args,
}) {
  final bin = containerEngineBin(engine);
  final session = engine == 'podman' ? podmanUserSession : '';
  final socket = _podmanSocketOrEmpty(engine, args);
  return '''
LC_ALL=C
$session
bin=\$(command -v $bin || true)
if [ -z "\$bin" ]; then echo missing engine; exit 1; fi
"\$bin" $args 2>/dev/null || $socket sudo -n "\$bin" $args
''';
}

String containerEngineScript({
  required String engine,
  required String body,
}) {
  final bin = containerEngineBin(engine);
  final session = engine == 'podman' ? podmanUserSession : '';
  final socket = _podmanSocketOrEmpty(engine, r'"$@"');
  return '''
LC_ALL=C
$session
bin=\$(command -v $bin || true)
if [ -z "\$bin" ]; then echo missing engine; exit 1; fi
run() { "\$bin" "\$@" 2>/dev/null || $socket sudo -n "\$bin" "\$@"; }
$body
''';
}
