import 'package:flutter/material.dart';
import 'package:kelola/app_version.dart';
import 'kelola_components.dart';
import 'kelola_theme.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/hosts/os_icon_kind.dart';

/// Isolated gallery of every widget in [kelola_components.dart].
/// Temporary debug destination — not a product screen.
class StyleGuideScreen extends StatelessWidget {
  const StyleGuideScreen({super.key});

  static const _spark = <double>[
    0.28, 0.32, 0.24, 0.48, 0.41, 0.62, 0.55, 0.78, 0.61, 0.84, 0.58, 0.71,
    0.44, 0.52, 0.38, 0.46,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Text(
          'Style guide',
          style: KelolaType.display(color: c.text, size: 16),
        ),
      ),
      body: ListView(
        padding: kelolaScrollPadding(context, left: 14, top: 8, right: 14, extraBottom: 16),
        children: [
          Text(
            'RISKBAND',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          RiskBand(
            risk: RiskLevel.read,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Read', style: KelolaType.display(color: c.text, size: 15)),
                Text(
                  'Inspect only. Permitted in read-only mode.',
                  style: KelolaType.body(color: c.muted, size: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          RiskBand(
            risk: RiskLevel.mutate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mutate', style: KelolaType.display(color: c.text, size: 15)),
                Text(
                  'Changes state. Single confirmation.',
                  style: KelolaType.body(color: c.muted, size: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          RiskBand(
            risk: RiskLevel.destructive,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destructive',
                  style: KelolaType.display(color: c.text, size: 15),
                ),
                Text(
                  'Data loss or lockout. Type the hostname.',
                  style: KelolaType.body(color: c.muted, size: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'SERVICEROW',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.read,
            status: HealthStatus.healthy,
            name: 'sshd.service',
            meta: 'active · 47d',
          ),
          const SizedBox(height: 6),
          ServiceRow(
            risk: RiskLevel.mutate,
            status: HealthStatus.failed,
            name: 'nginx.service',
            meta: 'failed · exit 1 · 09:12',
            pillText: 'restart',
            onTap: () {},
          ),
          const SizedBox(height: 6),
          ServiceRow(
            risk: RiskLevel.destructive,
            status: HealthStatus.healthy,
            name: 'apache2.service',
            meta: 'active · 47d',
            pillText: 'stop',
            onTap: () {},
          ),
          const SizedBox(height: 6),
          ServiceRow(
            risk: RiskLevel.read,
            status: HealthStatus.unknown,
            name: 'backup-01',
            meta: 'unreachable · last seen 3d ago',
          ),
          const SizedBox(height: 18),
          Text(
            'TOOLTILE',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ToolTile(label: 'Services', meta: 'systemd', onTap: () {}),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ToolTile(label: 'Logs', meta: 'journalctl', onTap: () {}),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'FILTERPILL',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            children: [
              FilterPill(label: 'Failed 2', selected: true, onTap: () {}),
              FilterPill(label: 'Running', selected: false, onTap: () {}),
              FilterPill(label: 'Enabled', selected: false, onTap: () {}),
              FilterPill(label: 'All', selected: false, onTap: () {}),
              FilterPill(
                label: 'live',
                selected: false,
                enabled: false,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'KELOLAINPUT',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const KelolaInput(label: 'Alias', hint: 'nas-01'),
          const SizedBox(height: 10),
          const KelolaInput(
            label: 'Address',
            hint: '192.168.1.24',
            mono: true,
          ),
          const SizedBox(height: 18),
          Text(
            'STATCARD',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Load 1m',
                  value: '0.84',
                  meterFraction: 0.21,
                  status: HealthStatus.healthy,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: StatCard(
                  label: 'Memory',
                  value: '61',
                  unit: '%',
                  meterFraction: 0.61,
                  status: HealthStatus.healthy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Disk /',
                  value: '78',
                  unit: '%',
                  meterFraction: 0.78,
                  status: HealthStatus.warning,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: StatCard(
                  label: 'Failed',
                  value: '2',
                  meterFraction: 1,
                  status: HealthStatus.failed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'SPARKLINE',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          RiskBand(
            risk: RiskLevel.read,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CPU',
                  style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
                ),
                Text('34%', style: KelolaType.display(color: c.text, size: 18)),
                Sparkline(values: _spark, color: c.amber),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'MUTATECONFIRMDIALOG',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const MutateConfirmDialog(
            title: 'Restart nginx.service?',
            body: 'This changes state on nas-01.',
            confirmLabel: 'restart',
          ),
          const SizedBox(height: 18),
          Text(
            'JOURNALLOGLINE',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const JournalLogLine(
            timestamp: '09:12:04',
            message: 'nginx: [emerg] bind() to 0.0.0.0:80',
            kind: JournalLineKind.error,
          ),
          const JournalLogLine(
            timestamp: '09:12:03',
            message: 'retrying in 1000ms',
            kind: JournalLineKind.warning,
          ),
          const JournalLogLine(
            timestamp: '09:12:01',
            message: 'Starting nginx',
            kind: JournalLineKind.info,
          ),
          const SizedBox(height: 18),
          Text(
            'KICKERLINE',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const KickerLine(
            machine: 'UBUNTU 26.04 · UP 3H',
            readOnly: true,
          ),
          const SizedBox(height: 8),
          const KickerLine(
            machine: 'DEBIAN 12 · UP 47D',
            readOnly: false,
          ),
          const SizedBox(height: 18),
          Text(
            'ACTIONABLEERROR',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          ActionableError.sudo(user: 'hendra'),
          const SizedBox(height: 18),
          Text(
            'DASHBOARDSTATUSLINE',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          DashboardStatusLine(
            checkedAt: DateTime.utc(2026, 9, 2, 7, 56),
            now: DateTime.utc(2026, 9, 2, 8),
          ),
          const SizedBox(height: 8),
          DashboardStatusLine(
            checkedAt: DateTime.utc(2026, 9, 2, 7, 56),
            now: DateTime.utc(2026, 9, 2, 8),
            readOnly: true,
          ),
          const SizedBox(height: 8),
          DashboardStatusLine(
            checkedAt: DateTime.utc(2026, 9, 2, 7, 56),
            now: DateTime.utc(2026, 9, 2, 8),
            sudoNeedsPassword: true,
            sudoUser: 'hendra',
          ),
          const SizedBox(height: 8),
          DashboardStatusLine(
            checkedAt: DateTime.utc(2026, 9, 2, 7, 56),
            now: DateTime.utc(2026, 9, 2, 8),
            readOnly: true,
            sudoNeedsPassword: true,
            sudoUser: 'hendra',
          ),
          const SizedBox(height: 18),
          Text(
            'HOSTSCHROMEACCENT',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: ColoredBox(
              color: c.ink,
              child: const HostsChromeAccent(),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'SECTIONSLAB',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 4),
          HostGroupTray(
            label: 'Needs attention',
            child: ServiceRow(
              risk: RiskLevel.read,
              status: HealthStatus.failed,
              leading: OsIcon.forOsId('debian'),
              name: 'nas-01',
              meta: '192.168.1.24 · Debian 12',
              detail: '2 failed · disk 91% · checked 4m ago',
              compact: true,
            ),
          ),
          HostGroupTray(
            label: 'Healthy',
            child: ServiceRow(
              risk: RiskLevel.read,
              status: HealthStatus.healthy,
              leading: OsIcon.forOsId('ubuntu'),
              name: 'vps-sg',
              meta: '203.0.113.9 · Ubuntu 24.04',
              detail: 'disk 40% · checked 2m ago',
              compact: true,
            ),
          ),
          HostGroupTray(
            label: 'Not checked',
            child: ServiceRow(
              risk: RiskLevel.read,
              status: HealthStatus.unknown,
              leading: OsIcon.forOsId(null),
              name: 'ub',
              meta: '127.0.0.1',
              compact: true,
            ),
          ),
          const SizedBox(height: 8),
          CollapsedHostGroup(
            label: 'HEALTHY · 184',
            onTap: () {},
          ),
          const SizedBox(height: 18),
          Text(
            'OSICON',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              OsIcon(kind: OsIconKind.ubuntu),
              SizedBox(width: 10),
              OsIcon(kind: OsIconKind.debian),
              SizedBox(width: 10),
              OsIcon(kind: OsIconKind.fedora),
              SizedBox(width: 10),
              OsIcon(kind: OsIconKind.alpine),
              SizedBox(width: 10),
              OsIcon(kind: OsIconKind.arch),
              SizedBox(width: 10),
              OsIcon(kind: OsIconKind.rhel),
              SizedBox(width: 10),
              OsIcon(kind: OsIconKind.linux),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'KELOLABRANDMARK',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const KelolaBrandMark(size: 22),
              const SizedBox(width: 8),
              Text(
                'Kelola',
                style: KelolaType.display(color: c.text, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'HOSTHEROCARD',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const HostHeroCard(
            alias: 'nas-01',
            endpoint: '192.168.1.24',
            os: 'Debian 12',
            connectionStatus: 'Connected',
            health: HealthStatus.healthy,
            osId: 'debian',
          ),
          const SizedBox(height: 18),
          Text(
            'FACTGROUP',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const FactGroup(
            heading: 'System',
            entries: [
              FactEntry(label: 'OS', value: 'Debian 12'),
              FactEntry(label: 'Init', value: 'systemd'),
              FactEntry(label: 'Arch', value: 'x86_64'),
              FactEntry(label: 'Cores', value: '4'),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'AUDITINSIGHTROW',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          AuditInsightRow(
            summary: const AuditWeekSummary(
              changes: 2,
              destructive: 1,
              failed: 36,
            ),
            onTap: () {},
          ),
          const SizedBox(height: 18),
          Text(
            'HOSTSCOLOPHON',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          const HostsColophon(version: kelolaAppVersion),
          const SizedBox(height: 18),
          Text(
            'DESTRUCTIVECONFIRMSHEET',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          DestructiveConfirmSheet(
            title: 'Stop sshd.service?',
            consequence: 'This is the service Kelola uses to reach nas-01.',
            warning:
                'You will lose access immediately. Recovery needs physical or console access to the machine.',
            confirmToken: 'nas-01',
            onConfirmed: () {},
          ),
        ],
      ),
    );
  }
}
