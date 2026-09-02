import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/domain/probes/process_signal_probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';

void main() {
  const facts = HostFacts.undiscovered;

  test('DashboardProbe audit title is the probe, never LC_ALL=C', () {
    const probe = DashboardProbe();
    final draft = AuditDraft.fromProbe(probe, facts);
    expect(draft.title, isNot(contains('LC_ALL')));
    expect(draft.title.toLowerCase(), isNot(contains('lc_all')));
    expect(draft.title, isNot(equals(probe.command(facts).trim().split('\n').first)));
    expect(draft.command, contains('LC_ALL=C'));
    expect(draft.title, 'Polled dashboard');
  });

  test('JournalProbe and HostFactsProbe titles are probe identity, not shell', () {
    const journaled = HostFacts(
      osId: 'ubuntu',
      osVersionId: '26.04',
      init: InitSystem.systemd,
      systemdVersion: 257,
      pkg: PackageManager.apt,
      fw: FirewallBackend.ufw,
      hasJournald: true,
      journalReadable: true,
      arch: 'x86_64',
    );
    expect(
      AuditDraft.fromProbe(const JournalProbe(), facts).title,
      'Read journal',
    );
    expect(
      AuditDraft.fromProbe(const JournalProbe(unit: 'nginx.service'), facts).title,
      'Read journal for nginx.service',
    );
    expect(
      AuditDraft.fromProbe(const HostFactsProbe(), facts).title,
      'Discovered host',
    );
    expect(const JournalProbe().command(journaled), contains('LC_ALL=C'));
    expect(const HostFactsProbe().command(facts), contains('LC_ALL=C'));
  });

  test('UnitActionProbe restart nginx humanizes to Restarted nginx.service', () {
    const probe = UnitActionProbe(
      unitName: 'nginx.service',
      verb: UnitVerb.restart,
    );
    expect(probe.auditTitle, 'Restarted nginx.service');
    expect(AuditDraft.fromProbe(probe, facts).command, isNot(equals(probe.auditTitle)));
  });

  test('CommandRunnerProbe title is Ran <command>, still mutate', () {
    const probe = CommandRunnerProbe('ls -la /var');
    expect(probe.auditTitle, 'Ran ls');
    expect(probe.risk.name, 'mutate');
  });

  test('mutate and destructive probes humanize without parsing the shell script', () {
    expect(
      const HostActionProbe(HostVerb.reboot).auditTitle,
      'Rebooted host',
    );
    expect(
      const ProcessSignalProbe(
        pid: 441,
        signal: ProcessSignal.term,
        commandName: 'nginx',
      ).auditTitle,
      'Sent SIGTERM to nginx (441)',
    );
    expect(
      ContainerActionProbe(
        row: const ContainerRow(
          id: 'abc',
          names: 'web',
          image: 'nginx',
          state: 'running',
          status: 'Up',
        ),
        verb: ContainerVerb.restart,
      ).auditTitle,
      'Restarted web',
    );
  });
}
