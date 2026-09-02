import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/facts/serial_mask.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

class HostDetailsScreen extends StatefulWidget {
  const HostDetailsScreen({
    super.key,
    required this.host,
    required this.facts,
    this.pinnedKey,
    this.connected = false,
    this.onEdit,
    this.onRevealSerial,
  });

  final Host host;
  final HostFacts facts;
  final PinnedHostKey? pinnedKey;
  final bool connected;
  final VoidCallback? onEdit;
  final Future<void> Function()? onRevealSerial;

  @override
  State<HostDetailsScreen> createState() => _HostDetailsScreenState();
}

class _HostDetailsScreenState extends State<HostDetailsScreen> {
  bool _serialRevealed = false;

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
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
            ],
          ),
          if (firmware.isNotEmpty)
            FactGroup(heading: 'Firmware', entries: firmware),
          if (network.isNotEmpty)
            FactGroup(heading: 'Network', entries: network),
          if (gpu.isNotEmpty) FactGroup(heading: 'Gpu', entries: gpu),
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
