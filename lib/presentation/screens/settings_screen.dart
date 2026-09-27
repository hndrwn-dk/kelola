import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/app_lock/app_lock_timeout.dart';
import 'package:kelola/domain/session_logs/session_log.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/presentation/pro_locked_sheet.dart';
import 'package:kelola/providers.dart';

/// Paid only when unlock says so. The build token (`std` / `ext`) is not this.
/// Fleet unlimited stands in for the unlock set: tunnels has a single
/// production read on the host dashboard.
bool entitlementIsPaid(Entitlement entitlement) {
  return entitlement.isUnlocked(ProFeature.fleetUnlimited);
}

/// Flip when localization is implemented. Does not add a language picker.
const kShowLanguageSetting = false;

/// Flip when a light theme exists. Does not add one.
const kShowThemeSetting = false;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _restoreNote;

  Future<void> _pickLockTimeout() async {
    final can = ref.read(appLockAvailableProvider).asData?.value ?? false;
    if (!can) {
      return;
    }
    final c = context.kc;
    final current = AppLockTimeout.fromSeconds(
      ref.read(appLockTimeoutProvider).asData?.value ?? 0,
    );
    final chosen = await showModalBottomSheet<AppLockTimeout>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KelolaRadii.lg),
        ),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) {
        return KelolaSheet(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < AppLockTimeout.values.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  ServiceRow(
                    risk: RiskLevel.read,
                    name: AppLockTimeout.values[i].label,
                    meta: AppLockTimeout.values[i] == current
                        ? 'selected'
                        : 'timeout',
                    onTap: () => Navigator.of(ctx).pop(AppLockTimeout.values[i]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) {
      return;
    }
    await ref.read(hostRepositoryProvider).setAppLockTimeoutSec(chosen.seconds);
    ref.invalidate(appLockTimeoutProvider);
  }

  Future<void> _pickRetention() async {
    final c = context.kc;
    final current = SessionLogRetention.fromDays(
      ref.read(sessionLogRetentionProvider).asData?.value ??
          kDefaultSessionLogRetentionDays,
    );
    final chosen = await showModalBottomSheet<SessionLogRetention>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KelolaRadii.lg),
        ),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) {
        return KelolaSheet(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < SessionLogRetention.values.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  ServiceRow(
                    risk: RiskLevel.read,
                    name: SessionLogRetention.values[i].label,
                    meta: SessionLogRetention.values[i] == current
                        ? 'selected'
                        : 'retention',
                    onTap: () =>
                        Navigator.of(ctx).pop(SessionLogRetention.values[i]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) {
      return;
    }
    await ref
        .read(hostRepositoryProvider)
        .setSessionLogRetentionDays(chosen.days);
    ref.invalidate(sessionLogRetentionProvider);
  }

  Future<void> _openFleetWatch() async {
    final entitlement = ref.read(entitlementProvider);
    if (!entitlement.isUnlocked(ProFeature.fleetWatch)) {
      await showProLockedSheet(
        context,
        title: 'Fleet watch',
        body: 'Background fleet watch refreshes selected hosts about hourly '
            'and alerts locally when a watched signal changes. '
            'This build keeps watch locked.',
        onPurchase: () => entitlement.purchase(),
      );
      return;
    }
    final hosts = ref.read(hostRepositoryProvider);
    var enabled = await hosts.fleetWatchEnabled();
    var thresholds = await hosts.fleetWatchThresholds();
    if (!mounted) {
      return;
    }
    final c = context.kc;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KelolaRadii.lg),
        ),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) {
        return KelolaSheet(
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    Text(
                      'Fleet watch',
                      style: KelolaType.display(color: c.text, size: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Roughly hourly. Local alerts only.',
                      style: KelolaType.body(color: c.muted, size: 13),
                    ),
                    const SizedBox(height: 12),
                    ServiceRow(
                      risk: RiskLevel.read,
                      name: enabled ? 'On' : 'Off',
                      meta: 'default off',
                      onTap: () async {
                        enabled = !enabled;
                        await ref
                            .read(fleetWatchControllerProvider)
                            .setEnabled(enabled);
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _WatchPillRow(
                      label: 'Disk',
                      values: const ['80', '90', '95'],
                      selected: '${thresholds.diskPercent}',
                      onPick: (raw) async {
                        thresholds = FleetWatchThresholds(
                          diskPercent: int.parse(raw),
                          memPercent: thresholds.memPercent,
                          failedUnits: thresholds.failedUnits,
                          containers: thresholds.containers,
                          reboot: thresholds.reboot,
                        );
                        await hosts.setFleetWatchThresholds(thresholds);
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    _WatchPillRow(
                      label: 'Memory',
                      values: const ['80', '90', '95'],
                      selected: '${thresholds.memPercent}',
                      onPick: (raw) async {
                        thresholds = FleetWatchThresholds(
                          diskPercent: thresholds.diskPercent,
                          memPercent: int.parse(raw),
                          failedUnits: thresholds.failedUnits,
                          containers: thresholds.containers,
                          reboot: thresholds.reboot,
                        );
                        await hosts.setFleetWatchThresholds(thresholds);
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    _WatchPillRow(
                      label: 'Failed units',
                      values: const ['1', '2', '5'],
                      selected: '${thresholds.failedUnits}',
                      onPick: (raw) async {
                        thresholds = FleetWatchThresholds(
                          diskPercent: thresholds.diskPercent,
                          memPercent: thresholds.memPercent,
                          failedUnits: int.parse(raw),
                          containers: thresholds.containers,
                          reboot: thresholds.reboot,
                        );
                        await hosts.setFleetWatchThresholds(thresholds);
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    _WatchPillRow(
                      label: 'Containers',
                      values: const ['1', '2', '5'],
                      selected: '${thresholds.containers}',
                      onPick: (raw) async {
                        thresholds = FleetWatchThresholds(
                          diskPercent: thresholds.diskPercent,
                          memPercent: thresholds.memPercent,
                          failedUnits: thresholds.failedUnits,
                          containers: int.parse(raw),
                          reboot: thresholds.reboot,
                        );
                        await hosts.setFleetWatchThresholds(thresholds);
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    _WatchPillRow(
                      label: 'Reboot',
                      values: const ['on', 'off'],
                      selected: thresholds.reboot ? 'on' : 'off',
                      onPick: (raw) async {
                        thresholds = FleetWatchThresholds(
                          diskPercent: thresholds.diskPercent,
                          memPercent: thresholds.memPercent,
                          failedUnits: thresholds.failedUnits,
                          containers: thresholds.containers,
                          reboot: raw == 'on',
                        );
                        await hosts.setFleetWatchThresholds(thresholds);
                        setSheet(() {});
                      },
                    ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    final result = await ref.read(entitlementProvider).restore();
    if (!mounted) {
      return;
    }
    setState(() {
      _restoreNote = switch (result) {
        ProPurchaseResult.unavailable => 'Nothing to restore on this build.',
        ProPurchaseResult.purchased => 'Purchase restored.',
        ProPurchaseResult.pending => 'Restore is still pending.',
        ProPurchaseResult.cancelled => 'Restore cancelled.',
        ProPurchaseResult.error => 'Restore did not complete. Try again.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeout = ref.watch(appLockTimeoutProvider).asData?.value ?? 0;
    final retentionDays = ref.watch(sessionLogRetentionProvider).asData?.value ??
        kDefaultSessionLogRetentionDays;
    final canAuth = ref.watch(appLockAvailableProvider).asData?.value ?? false;
    final lockReady = ref.watch(appLockAvailableProvider).hasValue;
    final c = context.kc;
    final entitlement = ref.watch(entitlementProvider);
    final paid = entitlementIsPaid(entitlement);
    final token = entitlement.sourceLabel.trim();
    final versionMeta = token.isEmpty
        ? '$kelolaAppVersion · build $kelolaVersionCode'
        : '$kelolaAppVersion · build $kelolaVersionCode · $token';
    return KelolaWashScaffold(
      appBar: AppBar(
        backgroundColor: c.ink.withValues(alpha: 0),
        surfaceTintColor: c.ink.withValues(alpha: 0),
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        leadingWidth: KelolaChromeIconButton.leadingWidth,
        leading: const Align(
          alignment: Alignment.center,
          child: KelolaBackButton(),
        ),
        titleSpacing: KelolaChromeIconButton.titleGap,
        title: Text(
          'Settings',
          style: KelolaType.display(color: c.text, size: 16),
        ),
        shape: Border(bottom: BorderSide(color: c.line)),
      ),
      body: ListView(
        padding: kelolaScrollPadding(
          context,
          left: 16,
          top: 12,
          right: 16,
        ),
        children: [
          HostGroupTray(
            label: 'App',
            child: Column(
              children: [
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Version',
                  meta: versionMeta,
                ),
                const SizedBox(height: 8),
                const ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Keys stay on this device',
                  meta: 'never leave this phone',
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'App lock',
                  meta: !lockReady
                      ? AppLockTimeout.off.label
                      : canAuth
                          ? AppLockTimeout.fromSeconds(timeout).label
                          : 'set a device screen lock first',
                  onTap: canAuth ? _pickLockTimeout : null,
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Session logs',
                  meta: SessionLogRetention.fromDays(retentionDays).label,
                  onTap: _pickRetention,
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Fleet watch',
                  meta: paid ? 'roughly hourly' : 'unlock required',
                  onTap: _openFleetWatch,
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: paid ? 'Paid' : 'Free',
                  meta: 'purchase status',
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Restore purchase',
                  meta: 'check this account',
                  onTap: _restore,
                ),
                if (_restoreNote != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _restoreNote!,
                      style: KelolaType.body(color: c.muted, size: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (kShowLanguageSetting || kShowThemeSetting) ...[
            const SizedBox(height: 8),
            HostGroupTray(
              label: 'Appearance',
              child: Column(
                children: [
                  if (kShowLanguageSetting)
                    const ServiceRow(
                      risk: RiskLevel.read,
                      name: 'Language',
                      meta: 'Not in this version',
                    ),
                  if (kShowLanguageSetting && kShowThemeSetting)
                    const SizedBox(height: 8),
                  if (kShowThemeSetting)
                    const ServiceRow(
                      risk: RiskLevel.read,
                      name: 'Theme',
                      meta: 'Not in this version',
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WatchPillRow extends StatelessWidget {
  const _WatchPillRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.onPick,
  });

  final String label;
  final List<String> values;
  final String selected;
  final Future<void> Function(String raw) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: KelolaType.body(color: c.muted, size: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final value in values)
              FilterPill(
                label: value,
                selected: value == selected,
                onTap: () => onPick(value),
              ),
          ],
        ),
      ],
    );
  }
}
