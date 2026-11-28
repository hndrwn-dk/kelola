import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/facts/serial_mask.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/sudo/kelola_sudo_files.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

class HostDetailsScreen extends StatefulWidget {
  const HostDetailsScreen({
    super.key,
    required this.host,
    this.jumpVia,
    required this.facts,
    this.pinnedKey,
    this.connected = false,
    this.onEdit,
    this.onRevealSerial,
    this.checkSudoRules,
    this.checkReaderRole,
    this.readSudoFiles,
    this.readSudoFilesWithPassword,
    this.removeSudoRule,
  });

  final Host host;
  final String? jumpVia;
  final HostFacts facts;
  final PinnedHostKey? pinnedKey;
  final bool connected;
  final VoidCallback? onEdit;
  final Future<void> Function()? onRevealSerial;

  /// Resolves true when the host's Kelola sudo rules are outdated.
  final Future<bool> Function()? checkSudoRules;

  /// Resolves true when the read-only Kubernetes reader role is outdated.
  final Future<bool> Function()? checkReaderRole;

  /// Reads the Kelola sudo files without a password ([KelolaSudoFilesProbe]).
  /// Null hides the "Kelola sudo rules" section (no live session).
  final Future<KelolaSudoFiles> Function()? readSudoFiles;

  /// Asks for the sudo password and reads the files with it.
  final Future<KelolaSudoFiles> Function(BuildContext context)?
  readSudoFilesWithPassword;

  /// Removes one line or a whole file, after the screen's
  /// [DestructiveConfirmSheet]: presence, the sudo password, then
  /// [KelolaSudoRemoveProbe]. Throws on failure.
  final Future<void> Function(BuildContext context, KelolaSudoRemoval removal)?
  removeSudoRule;

  @override
  State<HostDetailsScreen> createState() => _HostDetailsScreenState();
}

class _HostDetailsScreenState extends State<HostDetailsScreen> {
  bool _serialRevealed = false;
  bool _sudoRulesOutdated = false;
  bool _readerRoleOutdated = false;

  /// The Kelola sudo files as last read; null until the first read.
  KelolaSudoFiles? _sudoFiles;
  bool _sudoBusy = false;
  String? _sudoError;

  @override
  void initState() {
    super.initState();
    _checkSudoRules();
    _checkReaderRole();
    _readSudoFiles();
  }

  Future<void> _checkReaderRole() async {
    final check = widget.checkReaderRole;
    if (check == null) {
      return;
    }
    try {
      final outdated = await check();
      if (mounted) {
        setState(() => _readerRoleOutdated = outdated);
      }
    } catch (_) {
      // A warning that cannot be checked stays hidden.
      if (mounted) setState(() => _readerRoleOutdated = false);
    }
  }

  Future<void> _checkSudoRules() async {
    final check = widget.checkSudoRules;
    if (check == null) {
      return;
    }
    try {
      final outdated = await check();
      if (mounted) {
        setState(() => _sudoRulesOutdated = outdated);
      }
    } catch (_) {
      // A warning that cannot be checked stays hidden.
      if (mounted) setState(() => _sudoRulesOutdated = false);
    }
  }

  Future<void> _readSudoFiles() async {
    final read = widget.readSudoFiles;
    if (read == null) return;
    await _sudoRead(read);
  }

  Future<void> _sudoRead(Future<KelolaSudoFiles> Function() read) async {
    setState(() {
      _sudoBusy = true;
      _sudoError = null;
    });
    try {
      final files = await read();
      if (mounted) setState(() => _sudoFiles = files);
    } catch (e) {
      if (mounted) {
        setState(
          () => _sudoError = e is KelolaException
              ? e.message
              : 'Could not read the Kelola sudo rules.',
        );
      }
    } finally {
      if (mounted) setState(() => _sudoBusy = false);
    }
  }

  Future<void> _readSudoFilesWithPassword() async {
    final read = widget.readSudoFilesWithPassword;
    if (read == null || _sudoBusy) return;
    await _sudoRead(() => read(context));
  }

  /// [DestructiveConfirmSheet] (the exact command for a line, the file name
  /// for a whole file), then [HostDetailsScreen.removeSudoRule]; then the
  /// list is read again and the outdated-rules row checked again.
  Future<void> _confirmRemove(KelolaSudoFile file, String? line) async {
    final remove = widget.removeSudoRule;
    if (remove == null || _sudoBusy || widget.host.readOnly) return;
    final alias = widget.host.alias;
    final cmd = line == null ? null : kelolaSudoRuleCommand(line);
    var confirmed = false;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => KelolaSheet(
        child: DestructiveConfirmSheet(
          title: cmd == null
              ? 'Delete ${file.name}?'
              : 'Remove this sudo line?',
          consequence: cmd == null
              ? 'Kelola deletes ${file.path} on $alias. Every command in it '
                    'will need your sudo password again.'
              : 'Kelola removes "${describeKelolaSudoRule(cmd)}" from '
                    '${file.path} on $alias, checks the file with visudo and '
                    'confirms it on the host. Removing the last line deletes '
                    'the file.',
          warning: cmd == null
              ? 'Type ${file.name} to confirm.'
              : 'Type the exact command to confirm.',
          confirmToken: cmd ?? file.name,
          onConfirmed: () => confirmed = true,
        ),
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _sudoBusy = true);
    try {
      await remove(context, (path: file.path, line: line));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cmd == null ? 'Deleted ${file.name}' : 'Removed from ${file.name}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is KelolaException ? e.message : 'Could not change ${file.name}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sudoBusy = false);
    }
    if (!mounted) return;
    await _readSudoFiles();
    await _checkSudoRules();
    await _checkReaderRole();
  }

  List<Widget> _sudoRulesSection(BuildContext context) {
    final c = context.kc;
    final files = _sudoFiles;
    final readOnly = widget.host.readOnly;
    final canRemove =
        !readOnly && !_sudoBusy && widget.removeSudoRule != null;
    final note = KelolaType.body(color: c.muted, size: 12);
    final out = <Widget>[
      const SizedBox(height: 8),
      const SectionSlab('Kelola sudo rules'),
      if (readOnly) Text('Host is read-only.', style: note),
    ];
    if (_sudoError != null) {
      out.add(Text(_sudoError!, style: note));
    }
    if (files == null) {
      if (_sudoBusy) out.add(Text('Reading…', style: note));
      return out;
    }
    final shown = files.shown;
    if (shown.isEmpty) {
      out.add(Text('No Kelola sudo files on this host.', style: note));
      return out;
    }
    for (final f in shown) {
      final lines = f.lines;
      out
        ..add(const SizedBox(height: 8))
        ..add(
          Text(f.path, style: KelolaType.mono(color: c.text, size: 11.5)),
        )
        ..add(const SizedBox(height: 4));
      if (lines == null) continue;
      for (final l in lines) {
        out
          ..add(
            ServiceRow(
              risk: RiskLevel.destructive,
              compact: true,
              name: describeKelolaSudoRule(l),
              meta: kelolaSudoRuleCommand(l),
              onTap: canRemove ? () => _confirmRemove(f, l) : null,
            ),
          )
          ..add(const SizedBox(height: 4));
      }
      out
        ..add(
          ServiceRow(
            risk: RiskLevel.destructive,
            compact: true,
            name: 'Remove file',
            meta: f.name,
            onTap: canRemove ? () => _confirmRemove(f, null) : null,
          ),
        )
        ..add(const SizedBox(height: 4));
    }
    if (files.contentsNeedPassword) {
      final listed = files.listedKelola;
      out
        ..add(const SizedBox(height: 8))
        ..add(
          Text(
            'The file contents need the sudo password. '
            '${listed.isEmpty ? 'sudo -n -l reports no Kelola rule.' : 'sudo -n -l reports these Kelola rules:'}',
            style: note,
          ),
        )
        ..add(const SizedBox(height: 4));
      for (final cmd in listed) {
        out
          ..add(
            ServiceRow(
              risk: RiskLevel.read,
              compact: true,
              name: describeKelolaSudoRule(cmd),
              meta: cmd,
            ),
          )
          ..add(const SizedBox(height: 4));
      }
      if (widget.readSudoFilesWithPassword != null) {
        out.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _sudoBusy ? null : _readSudoFilesWithPassword,
              child: Text(
                'Read with password',
                style: KelolaType.display(color: c.amber, size: 13),
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final facts = widget.facts;
    final host = widget.host;
    final os = facts.label == 'unknown' ? '' : facts.label;
    final coresUnknown = facts.nprocCores == null;
    final fp = widget.pinnedKey?.fingerprint;
    final algo = widget.pinnedKey?.algorithm;
    final last = host.lastSeenAt;
    final firmware = _firmwareEntries(facts);
    final network = _networkEntries(facts.nics);
    final gpu = _gpuEntries(facts.gpu);

    return KelolaPage(
      title: 'Host details',
      bar: KelolaHostAppBar(
        hostAlias: host.alias,
        title: 'Host details',
      ),
      body: ListView(
        padding: kelolaScrollPadding(context, top: 8),
        children: [
          HostHeroCard(
            alias: host.alias,
            endpoint: host.endpoint,
            os: os,
            connectionStatus: _connectionStatus(),
            health: _connectionHealth(),
            osId: facts.osId.isEmpty ? host.osId : facts.osId,
          ),
          if (widget.onEdit != null) ...[
            const SizedBox(height: 10),
            KelolaPrimaryButton(label: 'Edit host', onTap: widget.onEdit!),
          ],
          FactGroup(
            heading: 'System',
            entries: [
              if (widget.jumpVia != null && widget.jumpVia!.isNotEmpty)
                FactEntry(
                  label: 'Jump',
                  value: widget.jumpVia!,
                ),
              FactEntry(
                label: 'OS',
                value: os.isEmpty ? 'unknown' : os,
                mono: os.isNotEmpty,
              ),
              if (facts.model != null && facts.model!.isNotEmpty)
                FactEntry(label: 'Model', value: facts.model!, mono: true),
              ...?_serialEntry(facts),
              FactEntry(label: 'Init', value: facts.init.name, mono: true),
              FactEntry(
                label: 'Arch',
                value: facts.arch.isEmpty ? 'unknown' : facts.arch,
                mono: facts.arch.isNotEmpty,
              ),
              FactEntry(
                label: 'Cores',
                value: coresUnknown ? 'unknown' : '${facts.nprocCores}',
                mono: !coresUnknown,
              ),
            ],
          ),
          FactGroup(
            heading: 'Tooling',
            entries: [
              FactEntry(
                label: 'Packages',
                value: facts.pkg.name == 'unknown' ? 'unknown' : facts.pkg.name,
                mono: facts.pkg.name != 'unknown',
              ),
              FactEntry(
                label: 'Firewall',
                value: facts.fw.name == 'none' ? 'none' : facts.fw.name,
                mono: true,
              ),
              FactEntry(
                label: 'Runtimes',
                value: facts.runtimes.isEmpty
                    ? 'none'
                    : facts.runtimes.join(' '),
                mono: facts.runtimes.isNotEmpty,
              ),
              FactEntry(
                label: 'Journal',
                value: facts.journalReadable ? 'readable' : 'not readable',
                mono: false,
              ),
            ],
          ),
          FactGroup(
            heading: 'Security',
            entries: [
              FactEntry(
                label: 'Key type',
                value: (algo == null || algo.isEmpty) ? 'unknown' : algo,
                mono: algo != null && algo.isNotEmpty,
              ),
              FactEntry(
                label: 'Host-key fingerprint',
                value: (fp == null || fp.isEmpty) ? 'unknown' : fp,
                mono: fp != null && fp.isNotEmpty,
              ),
              FactEntry(
                label: 'Last connected',
                value: last == null ? 'never' : Host.ageLabel(last),
                mono: last != null,
              ),
              FactEntry(
                label: 'Service control',
                value: serviceControlLabel(
                  readOnly: host.readOnly,
                  sudoNeedsPassword: host.sudoNeedsPassword,
                ),
                mono: false,
              ),
              if (_sudoRulesOutdated)
                const FactEntry(
                  label: 'Kelola sudo',
                  value: kelolaSudoRulesOutdatedCopy,
                  mono: false,
                ),
              if (_readerRoleOutdated)
                const FactEntry(
                  label: 'Kubernetes reader',
                  value: kelolaReaderRoleOutdatedCopy,
                  mono: false,
                ),
            ],
          ),
          if (firmware.isNotEmpty)
            FactGroup(heading: 'Firmware', entries: firmware),
          if (network.isNotEmpty)
            FactGroup(heading: 'Network', entries: network),
          if (gpu.isNotEmpty) FactGroup(heading: 'Gpu', entries: gpu),
          if (widget.readSudoFiles != null) ..._sudoRulesSection(context),
        ],
      ),
    );
  }

  List<FactEntry>? _serialEntry(HostFacts facts) {
    if (facts.serialStatus == SerialStatus.requiresRoot) {
      return const [
        FactEntry(label: 'Serial', value: 'requires root', mono: false),
      ];
    }
    final serial = facts.serial;
    if (facts.serialStatus != SerialStatus.available || serial == null) {
      return null;
    }
    final masked = maskSerial(serial);
    if (masked == null) {
      return null;
    }
    return [
      FactEntry(
        label: 'Serial',
        value: _serialRevealed ? serial : masked,
        mono: true,
        onTap: _onSerialTap,
      ),
    ];
  }

  Future<void> _onSerialTap() async {
    final serial = widget.facts.serial;
    if (serial == null || serial.isEmpty) {
      return;
    }
    final firstReveal = !_serialRevealed;
    if (firstReveal) {
      setState(() => _serialRevealed = true);
      await widget.onRevealSerial?.call();
    }
    await Clipboard.setData(ClipboardData(text: serial));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }

  List<FactEntry> _firmwareEntries(HostFacts facts) {
    return [
      if (facts.biosVendor != null && facts.biosVendor!.isNotEmpty)
        FactEntry(label: 'Vendor', value: facts.biosVendor!, mono: true),
      if (facts.biosVersion != null && facts.biosVersion!.isNotEmpty)
        FactEntry(label: 'Version', value: facts.biosVersion!, mono: true),
      if (facts.biosDate != null && facts.biosDate!.isNotEmpty)
        FactEntry(label: 'Date', value: facts.biosDate!, mono: true),
    ];
  }

  List<FactEntry> _networkEntries(List<HostNic> nics) {
    final entries = <FactEntry>[];
    final prefix = nics.length > 1;
    for (final nic in nics) {
      if (!prefix) {
        entries.add(FactEntry(label: 'Interface', value: nic.name, mono: true));
      }
      if (nic.ipv4 != null && nic.ipv4!.isNotEmpty) {
        entries.add(
          FactEntry(
            label: prefix ? '${nic.name} IPv4' : 'IPv4',
            value: nic.ipv4!,
            mono: true,
          ),
        );
      }
      if (nic.ipv6 != null && nic.ipv6!.isNotEmpty) {
        entries.add(
          FactEntry(
            label: prefix ? '${nic.name} IPv6' : 'IPv6',
            value: nic.ipv6!,
            mono: true,
          ),
        );
      }
      if (nic.mac != null && nic.mac!.isNotEmpty) {
        entries.add(
          FactEntry(
            label: prefix ? '${nic.name} MAC' : 'MAC',
            value: nic.mac!,
            mono: true,
          ),
        );
      }
    }
    return entries;
  }

  List<FactEntry> _gpuEntries(HostGpu? gpu) {
    if (gpu == null) {
      return const [];
    }
    return [
      if (gpu.model != null && gpu.model!.isNotEmpty)
        FactEntry(label: 'Model', value: gpu.model!, mono: true),
      if (gpu.vram != null && gpu.vram!.isNotEmpty)
        FactEntry(label: 'VRAM', value: gpu.vram!, mono: true),
      if (gpu.driver != null && gpu.driver!.isNotEmpty)
        FactEntry(label: 'Driver', value: gpu.driver!, mono: true),
    ];
  }

  String _connectionStatus() {
    if (widget.connected) {
      return 'Connected';
    }
    if (widget.host.lastSeenAt == null) {
      return 'Never connected';
    }
    return 'Disconnected';
  }

  HealthStatus _connectionHealth() {
    if (widget.connected) {
      return HealthStatus.healthy;
    }
    if (widget.host.lastSeenAt == null) {
      return HealthStatus.unknown;
    }
    return HealthStatus.failed;
  }
}
