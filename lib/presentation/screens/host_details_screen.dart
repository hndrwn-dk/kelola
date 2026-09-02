import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

class HostDetailsScreen extends StatelessWidget {
  const HostDetailsScreen({
    super.key,
    required this.host,
    required this.facts,
  });

  final Host host;
  final HostFacts facts;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      (host.alias, host.endpoint),
      ('User', host.username),
      if (facts.label.isNotEmpty && facts.label != 'unknown')
        ('OS', facts.label),
      if (facts.init.name.isNotEmpty) ('Init', facts.init.name),
      if (facts.pkg.name.isNotEmpty && facts.pkg.name != 'unknown')
        ('Packages', facts.pkg.name),
      if (facts.fw.name.isNotEmpty && facts.fw.name != 'none')
        ('Firewall', facts.fw.name),
      if (facts.arch.isNotEmpty) ('Arch', facts.arch),
      if (facts.runtimes.isNotEmpty) ('Runtimes', facts.runtimes.join(' ')),
      if (facts.nprocCores != null) ('Cores', '${facts.nprocCores}'),
      ('Journal', facts.journalReadable ? 'readable' : 'not readable'),
    ];

    return KelolaPage(
      title: 'Host details',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          const SectionSlab('Facts'),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            ServiceRow(
              risk: RiskLevel.read,
              name: rows[i].$1,
              meta: rows[i].$2,
            ),
          ],
        ],
      ),
    );
  }
}
