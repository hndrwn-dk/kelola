import 'dart:convert';
import 'dart:math';

import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/units/service_unit.dart';

const sudoRequiredTitle = 'sudo needs a password';

const sudoMutateWillFail =
    '$sudoRequiredTitle — mutate actions will fail';

const sudoRequiredBody =
    'This host\'s sudo asks for a password, so mutate actions will fail. '
    'Kelola never prompts for a sudo password. When a specific mutate fails, '
    'Kelola shows the sudoers or polkit rule for that command only. '
    'Reading unit status, reading the journal (usermod -aG systemd-journal), '
    'and systemctl --user need no sudo. Kelola stays useful with zero sudo '
    'config. Probes that need a shell cannot be made passwordless.';

const visudoKelolaPath = '/etc/sudoers.d/kelola';
const visudoKelolaCommand = 'sudo visudo -f /etc/sudoers.d/kelola';
const polkitKelolaPath = '/etc/polkit-1/rules.d/49-kelola.rules';

enum SudoHintKind {
  generic,
  systemd,
  hostReboot,
  hostPoweroff,
  dropCaches,
  container,
  containerPrune,
  containerRead,
  processSignal,
  packages,
  firewall,
}

class SudoHintContext {
  const SudoHintContext({
    this.kind = SudoHintKind.generic,
    this.unit,
    this.verb,
    this.binary,
    this.target,
  });

  const SudoHintContext.dropCaches() : this(kind: SudoHintKind.dropCaches);

  factory SudoHintContext.systemd({
    required String unit,
    required String verb,
  }) {
    return SudoHintContext(
      kind: SudoHintKind.systemd,
      unit: unit,
      verb: verb,
      binary: 'systemctl',
    );
  }

  factory SudoHintContext.container({
    required String engine,
    required String verb,
    String? target,
  }) {
    final bin = engine == 'podman' ? '/usr/bin/podman' : '/usr/bin/docker';
    return SudoHintContext(
      kind: SudoHintKind.container,
      binary: bin,
      verb: verb,
      target: target,
    );
  }

  /// Starts the hint fields in a [SudoRequiredException] message. Error text
  /// from a host goes through the same [tryParse], so the marker is random per
  /// run: only this app can write it.
  static final wireMarker = '---KELOLA_SUDO-${_randomHex()}---';

  static String _randomHex() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  final SudoHintKind kind;
  final String? unit;
  final String? verb;
  final String? binary;
  final String? target;

  String toWire() {
    // JSON keeps a newline in a value from starting a field of its own.
    String field(String key, String value) => '$key=${jsonEncode(value)}';
    return [
      field('kind', kind.name),
      if (unit != null && unit!.isNotEmpty) field('unit', unit!),
      if (verb != null && verb!.isNotEmpty) field('verb', verb!),
      if (binary != null && binary!.isNotEmpty) field('binary', binary!),
      if (target != null && target!.isNotEmpty) field('target', target!),
    ].join('\n');
  }

  static SudoHintContext tryParse(String message) {
    final i = message.indexOf(wireMarker);
    if (i < 0) {
      return const SudoHintContext();
    }
    final map = <String, String>{};
    for (final line in message.substring(i + wireMarker.length).split('\n')) {
      final eq = line.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      final key = line.substring(0, eq).trim();
      final value = _decodeField(line.substring(eq + 1).trim());
      if (value == null || map.containsKey(key)) {
        return const SudoHintContext();
      }
      map[key] = value;
    }
    final kindName = map['kind'];
    final kind = SudoHintKind.values.where((k) => k.name == kindName);
    return SudoHintContext(
      kind: kind.isEmpty ? SudoHintKind.generic : kind.first,
      unit: _emptyToNull(map['unit']),
      verb: _emptyToNull(map['verb']),
      binary: _emptyToNull(map['binary']),
      target: _emptyToNull(map['target']),
    );
  }

  static String? _decodeField(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is String ? value : null;
    } on FormatException {
      return null;
    }
  }

  static String? _emptyToNull(String? v) {
    if (v == null || v.isEmpty) {
      return null;
    }
    return v;
  }
}

class SudoHint {
  const SudoHint({required this.body, required this.snippet});

  final String body;
  final String snippet;
}

String serviceControlLabel({
  required bool readOnly,
  required bool sudoNeedsPassword,
}) {
  if (readOnly || sudoNeedsPassword) {
    return 'none — read only';
  }
  return 'sudo';
}

SudoHint kelolaSudoHint({
  String user = 'YOURUSER',
  SudoHintContext context = const SudoHintContext(),
}) {
  switch (context.kind) {
    case SudoHintKind.dropCaches:
      return SudoHint(
        body:
            'This probe runs a shell (sudo -n sh -c). Passwordless access to a '
            'shell is full root, so Kelola will not suggest a sudoers line. '
            '$sudoNeedsNoSudoCopy',
        snippet:
            'This probe cannot be passwordless.\n'
            'Passwordless access to a shell would be full root with no password.\n'
            '# For other commands, use visudo so a syntax error cannot lock sudo:\n'
            '# $visudoKelolaCommand\n',
      );
    case SudoHintKind.systemd:
      final unit = context.unit ?? 'UNIT.service';
      final verb = context.verb ?? 'restart';
      if (!isSudoersSafeUnitName(unit) ||
          !UnitVerb.values.any((v) => v.name == verb)) {
        return _binaryHint(
          user: user,
          spec: '/usr/bin/systemctl',
          bodyLead: 'this unit action',
          safe: false,
        );
      }
      final sudoers = '$user ALL=(root) NOPASSWD: '
          '/usr/bin/systemctl $verb ${_sudoersEscape(unit)}';
      return SudoHint(
        body:
            'This host\'s sudo asks for a password, so this mutate failed. '
            'Kelola never prompts for a sudo password on daily probes. '
            'Use Enable Kelola sudo, or add a NOPASSWD line for this unit only '
            'at $visudoKelolaPath (mode 0440), or a polkit rule limited to '
            '$unit. '
            '$sudoNeedsNoSudoCopy',
        snippet: '# path: $visudoKelolaPath  mode: 0440\n'
            '$visudoKelolaCommand\n'
            '# then paste:\n'
            '$sudoers\n'
            '\n'
            '${_polkitRule(user: user, unit: unit, verb: verb)}',
      );
    case SudoHintKind.hostReboot:
      return _binaryHint(
        user: user,
        spec: '/usr/sbin/reboot',
        bodyLead: 'reboot',
      );
    case SudoHintKind.hostPoweroff:
      return _binaryHint(
        user: user,
        spec: '/usr/sbin/poweroff',
        bodyLead: 'poweroff',
      );
    case SudoHintKind.container:
    case SudoHintKind.containerPrune:
    case SudoHintKind.containerRead:
      final bin = context.binary ?? '/usr/bin/docker';
      final verb = context.verb ?? 'inspect';
      final target = context.target;
      if (target == null || target.isEmpty) {
        final spec = '$bin $verb';
        return _binaryHint(user: user, spec: spec, bodyLead: spec);
      }
      final safe = _containerName.hasMatch(target);
      return _binaryHint(
        user: user,
        spec: '$bin $verb $target',
        bodyLead: safe ? '$bin $verb $target' : '$bin $verb',
        safe: safe,
      );
    case SudoHintKind.processSignal:
      final sig = context.verb ?? 'TERM';
      final pid = context.target ?? 'PID';
      return _binaryHint(
        user: user,
        spec: '/usr/bin/kill -s $sig $pid',
        bodyLead: 'this signal',
      );
    case SudoHintKind.packages:
      final spec = context.binary ?? '/usr/bin/apt-get -y upgrade';
      return _binaryHint(user: user, spec: spec, bodyLead: spec);
    case SudoHintKind.firewall:
      final spec = context.binary ?? '/usr/bin/firewall-cmd --list-all';
      return _binaryHint(user: user, spec: spec, bodyLead: spec);
    case SudoHintKind.generic:
      return SudoHint(
        body: sudoRequiredBody,
        snippet:
            '# path: $visudoKelolaPath  mode: 0440\n'
            '$visudoKelolaCommand\n'
            '# Prefer Enable Kelola sudo on the host dashboard for a guided apply.\n'
            '# Kelola will show a command-specific rule when a mutate fails.\n'
            '# Never grant passwordless access to a shell or to docker/systemctl without arguments.\n'
            '# systemd alternative: a polkit rule at $polkitKelolaPath limited to one unit.\n',
      );
  }
}

const sudoNeedsNoSudoCopy =
    'Reading unit status, reading the journal (usermod -aG systemd-journal), '
    'and systemctl --user need no sudo.';

/// Characters that end or break a sudoers command unless escaped, as in
/// `Dpkg::Options`.
String _sudoersEscape(String spec) => spec.replaceAllMapped(
      RegExp(r'[\\,:#]'),
      (m) => '\\${m[0]}',
    );

/// Sudoers wildcards, and control characters that would end the rule's line.
final _sudoersPattern = RegExp(r'[*?\[\]!^$\x00-\x1f\x7f\u0085  ]');

/// One container name, as docker and podman allow it.
final _containerName = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$');

SudoHint _binaryHint({
  required String user,
  required String spec,
  required String bodyLead,
  bool safe = true,
}) {
  // sudoers reads a command with no arguments as "any arguments"; "" means none.
  final command = spec.contains(' ') ? spec : '$spec ""';
  // Values in a spec can come from the host. Never hand back a pattern.
  final rule = !safe || spec.contains(_sudoersPattern)
      ? '# This command cannot be written as a safe sudoers rule.'
      : '$user ALL=(root) NOPASSWD: ${_sudoersEscape(command)}';
  return SudoHint(
    body:
        'This host\'s sudo asks for a password, so $bodyLead failed. '
        'Kelola never prompts for a sudo password on daily probes. '
        'Use Enable Kelola sudo, or add a NOPASSWD line for this command only '
        'at $visudoKelolaPath (mode 0440). $sudoNeedsNoSudoCopy',
    snippet: '# path: $visudoKelolaPath  mode: 0440\n'
        '$visudoKelolaCommand\n'
        '# then paste:\n'
        '$rule\n',
  );
}

String _polkitRule({
  required String user,
  required String unit,
  required String verb,
}) {
  final jsUnit = unit.replaceAll(r'\', r'\\');
  return '// $polkitKelolaPath\n'
      'polkit.addRule(function(action, subject) {\n'
      '    if (action.id == "org.freedesktop.systemd1.manage-units" &&\n'
      '        action.lookup("unit") == "$jsUnit" &&\n'
      '        action.lookup("verb") == "$verb" &&\n'
      '        subject.user == "$user") {\n'
      '        return polkit.Result.YES;\n'
      '    }\n'
      '});\n';
}

String kelolaSudoersLine({
  String user = 'YOURUSER',
  SudoHintContext context = const SudoHintContext(),
}) {
  return kelolaSudoHint(user: user, context: context).snippet;
}

bool looksLikeSudoRequired(Object error) {
  final s = error.toString().toLowerCase();
  if (!s.contains('sudo')) {
    return false;
  }
  return s.contains('password') ||
      s.contains('interactive authentication') ||
      s.contains('no tty') ||
      s.contains('askpass') ||
      s.contains('a terminal is required');
}
