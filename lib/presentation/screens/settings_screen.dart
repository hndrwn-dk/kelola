import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/app_lock/app_lock_timeout.dart';
import 'package:kelola/domain/session_logs/session_log.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/support/support_links.dart';
import 'package:kelola/domain/vault/vault.dart';
import 'package:kelola/presentation/host_env/env_bindings_sheet.dart';
import 'package:kelola/presentation/pro_locked_sheet.dart';
import 'package:kelola/presentation/screens/help_screen.dart';
import 'package:kelola/providers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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

typedef SettingsLaunchUrl = Future<bool> Function(Uri uri);
typedef SettingsShare = Future<void> Function(String text, {String? subject});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.launchUrlFn,
    this.shareFn,
  });

  final SettingsLaunchUrl? launchUrlFn;
  final SettingsShare? shareFn;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _restoreNote;

  Future<void> _pickScreenshots() async {
    final c = context.kc;
    final allowed = ref.read(allowScreenshotsProvider).asData?.value ?? false;
    final chosen = await showModalBottomSheet<bool>(
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
                Text(
                  'Screenshots',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'While App lock is on, Kelola blocks screenshots and screen '
                  'recording. Allowing them can capture host names, addresses '
                  'and command output. Below Android 13 and on iOS it also '
                  'shows the last screen in the app switcher while locked.',
                  style: KelolaType.body(color: c.muted, size: 13),
                ),
                const SizedBox(height: 12),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Blocked',
                  meta: allowed ? 'with App lock' : 'selected',
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Allowed',
                  meta: allowed ? 'selected' : 'always',
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || chosen == allowed) {
      return;
    }
    await ref.read(hostRepositoryProvider).setAllowScreenshots(chosen);
    ref.invalidate(allowScreenshotsProvider);
  }

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

  Future<void> _openVault() async {
    final c = context.kc;
    final remote = ref.read(vaultControllerProvider).remoteUnlocked;
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
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Vault',
                    style: KelolaType.display(color: c.text, size: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Passphrase-sealed blob. File export is free. '
                    'LAN and the host copy need unlock.',
                    style: KelolaType.body(color: c.muted, size: 13),
                  ),
                  const SizedBox(height: 12),
                  ServiceRow(
                    risk: RiskLevel.read,
                    name: 'Export file',
                    meta: 'share sealed blob',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _exportVaultFile();
                    },
                  ),
                  const SizedBox(height: 6),
                  ServiceRow(
                    risk: RiskLevel.mutate,
                    name: 'Import file',
                    meta: 'paste sealed blob',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _importVaultFile();
                    },
                  ),
                  const SizedBox(height: 6),
                  ServiceRow(
                    risk: RiskLevel.read,
                    name: 'Remote vault',
                    meta: remote ? '~/.kelola/vault.age' : 'unlock required',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _openRemoteVault(remote);
                    },
                  ),
                  const SizedBox(height: 6),
                  ServiceRow(
                    risk: RiskLevel.read,
                    name: 'Pair on LAN',
                    meta: remote ? 'X25519 handshake' : 'unlock required',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _openLanVault(remote);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _askPassphrase(String title) async {
    final controller = TextEditingController();
    final c = context.kc;
    final ok = await showModalBottomSheet<bool>(
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
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: KelolaType.display(color: c.text, size: 16)),
                const SizedBox(height: 10),
                KelolaInput(
                  label: 'passphrase',
                  controller: controller,
                ),
                const SizedBox(height: 10),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Continue',
                  meta: 'not stored',
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );
    final text = controller.text;
    controller.dispose();
    if (ok != true || text.isEmpty) {
      return null;
    }
    return text;
  }

  Future<void> _showDiff(VaultDiff diff) async {
    if (!mounted) {
      return;
    }
    final c = context.kc;
    final apply = await showModalBottomSheet<bool>(
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
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Vault diff',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  diff.summary,
                  style: KelolaType.body(color: c.muted, size: 13),
                ),
                const SizedBox(height: 12),
                ServiceRow(
                  risk: RiskLevel.mutate,
                  name: 'Apply',
                  meta: 'enroll this device after',
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (apply == true) {
      await ref.read(vaultControllerProvider).applyImport(diff);
    }
  }

  Future<void> _exportVaultFile() async {
    final passphrase = await _askPassphrase('Export vault');
    if (passphrase == null || !mounted) {
      return;
    }
    final blob = await ref.read(vaultControllerProvider).exportSealed(passphrase);
    await Share.share(blob, subject: 'Kelola vault');
  }

  Future<void> _importVaultFile() async {
    final passphrase = await _askPassphrase('Import vault');
    if (passphrase == null || !mounted) {
      return;
    }
    final paste = TextEditingController();
    final c = context.kc;
    final raw = await showModalBottomSheet<String>(
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
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Paste sealed blob',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 10),
                KelolaInput(label: 'blob', controller: paste, mono: true),
                const SizedBox(height: 10),
                ServiceRow(
                  risk: RiskLevel.mutate,
                  name: 'Preview',
                  meta: 'diff before apply',
                  onTap: () => Navigator.of(ctx).pop(paste.text),
                ),
              ],
            ),
          ),
        );
      },
    );
    paste.dispose();
    if (raw == null || raw.trim().isEmpty || !mounted) {
      return;
    }
    final diff = await ref
        .read(vaultControllerProvider)
        .previewImport(raw.trim(), passphrase);
    await _showDiff(diff);
  }

  Future<void> _openRemoteVault(bool unlocked) async {
    if (!unlocked) {
      await showProLockedSheet(
        context,
        title: 'Remote vault',
        body: 'A passphrase-sealed copy on a host you already administer. '
            'This build keeps remote vault locked.',
        priceLabel: ref.read(entitlementProvider).priceLabel,
        onPurchase: () => ref.read(entitlementProvider).purchase(),
      );
      return;
    }
    final hosts = await ref.read(hostRepositoryProvider).list();
    if (!mounted) {
      return;
    }
    final c = context.kc;
    final host = await showModalBottomSheet<Host>(
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
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < hosts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  ServiceRow(
                    risk: RiskLevel.read,
                    name: hosts[i].alias,
                    meta: '~/.kelola/vault.age',
                    onTap: () => Navigator.of(ctx).pop(hosts[i]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (host == null || !mounted) {
      return;
    }
    final passphrase = await _askPassphrase('Remote vault');
    if (passphrase == null || !mounted) {
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.kc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KelolaRadii.lg),
        ),
        side: BorderSide(color: context.kc.line),
      ),
      builder: (ctx) {
        return KelolaSheet(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ServiceRow(
                  risk: RiskLevel.mutate,
                  name: 'Push',
                  meta: host.alias,
                  onTap: () => Navigator.of(ctx).pop('push'),
                ),
                const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Pull',
                  meta: host.alias,
                  onTap: () => Navigator.of(ctx).pop('pull'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null || !mounted) {
      return;
    }
    final vault = ref.read(vaultControllerProvider);
    if (action == 'push') {
      await vault.pushRemote(
        host: host,
        passphrase: passphrase,
        ref: ref,
        context: context,
      );
      return;
    }
    await _showDiff(
      await vault.pullRemote(
        host: host,
        passphrase: passphrase,
        ref: ref,
        context: context,
      ),
    );
  }

  Future<void> _openLanVault(bool unlocked) async {
    if (!unlocked) {
      await showProLockedSheet(
        context,
        title: 'Pair on LAN',
        body: 'Ephemeral X25519 handshake on the local network. '
            'This build keeps LAN pairing locked.',
        priceLabel: ref.read(entitlementProvider).priceLabel,
        onPurchase: () => ref.read(entitlementProvider).purchase(),
      );
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Offer pair',
                  meta: 'show token',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final token =
                        await ref.read(vaultControllerProvider).startLanOffer();
                    if (!mounted) {
                      return;
                    }
                    final passphrase = await _askPassphrase('LAN receive');
                    if (passphrase == null || !mounted) {
                      return;
                    }
                    await showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: context.kc.surface,
                      builder: (tokenCtx) {
                        return KelolaSheet(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                            child: SelectableText(
                              token,
                              style: KelolaType.mono(
                                color: context.kc.text,
                                size: 11,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                    if (!mounted) {
                      return;
                    }
                    await _showDiff(
                      await ref
                          .read(vaultControllerProvider)
                          .receiveLan(passphrase),
                    );
                  },
                ),
                const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.mutate,
                  name: 'Join pair',
                  meta: 'paste token',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final tokenCtrl = TextEditingController();
                    final token = await showModalBottomSheet<String>(
                      context: context,
                      backgroundColor: context.kc.surface,
                      builder: (joinCtx) {
                        return KelolaSheet(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                KelolaInput(
                                  label: 'token',
                                  controller: tokenCtrl,
                                  mono: true,
                                ),
                                const SizedBox(height: 10),
                                ServiceRow(
                                  risk: RiskLevel.mutate,
                                  name: 'Send',
                                  meta: 'sealed blob',
                                  onTap: () =>
                                      Navigator.of(joinCtx).pop(tokenCtrl.text),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                    tokenCtrl.dispose();
                    if (token == null || token.trim().isEmpty || !mounted) {
                      return;
                    }
                    final passphrase = await _askPassphrase('LAN send');
                    if (passphrase == null || !mounted) {
                      return;
                    }
                    await ref
                        .read(vaultControllerProvider)
                        .sendLan(token.trim(), passphrase);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openProPurchase() {
    final entitlement = ref.read(entitlementProvider);
    return showProLockedSheet(
      context,
      title: 'Kelola Pro',
      body: 'Pro unlocks unlimited fleet, tunnels, '
          'multi-host snippets, and vault sync.',
      priceLabel: entitlement.priceLabel,
      onPurchase: () => entitlement.purchase(),
    );
  }

  Future<void> _restore() async {
    final result = await ref.read(entitlementProvider).restore();
    if (!mounted) {
      return;
    }
    setState(() {
      _restoreNote = switch (result) {
        ProPurchaseResult.unavailable =>
          'Nothing to restore for this Google account.',
        ProPurchaseResult.purchased => 'Kelola Pro restored.',
        ProPurchaseResult.pending => 'Restore is still pending.',
        ProPurchaseResult.cancelled => 'Restore cancelled.',
        ProPurchaseResult.error => 'Restore did not complete. Try again.',
      };
    });
  }

  Future<void> _openSupportUrl(String url) async {
    final launch = widget.launchUrlFn ??
        ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
    try {
      final ok = await launch(Uri.parse(url));
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link.')),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link.')),
      );
    }
  }

  Future<void> _shareKelola() async {
    final share = widget.shareFn ??
        ((text, {subject}) async {
          await Share.share(text, subject: subject);
        });
    try {
      await share(kKelolaShareText, subject: kKelolaShareSubject);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share.')),
      );
    }
  }

  void _openHelp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HelpScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeout = ref.watch(appLockTimeoutProvider).asData?.value ?? 0;
    final screenshotsAllowed =
        ref.watch(allowScreenshotsProvider).asData?.value ?? false;
    final retentionDays = ref.watch(sessionLogRetentionProvider).asData?.value ??
        kDefaultSessionLogRetentionDays;
    final canAuth = ref.watch(appLockAvailableProvider).asData?.value ?? false;
    final lockReady = ref.watch(appLockAvailableProvider).hasValue;
    final c = context.kc;
    ref.watch(entitlementRevisionProvider);
    final entitlement = ref.watch(entitlementProvider);
    final paid = entitlementIsPaid(entitlement);
    final price = entitlement.priceLabel?.trim();
    final priced = price != null && price.isNotEmpty;
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
                  name: 'Screenshots',
                  meta: screenshotsAllowed || timeout == 0
                      ? 'allowed'
                      : 'blocked with App lock',
                  onTap: _pickScreenshots,
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
                  name: 'Environments',
                  meta: 'tag variables',
                  onTap: () => showTagEnvironmentsSheet(context: context),
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Vault',
                  meta: 'encrypted export',
                  onTap: _openVault,
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: paid ? 'Paid' : 'Free',
                  meta: paid
                      ? 'Kelola Pro'
                      : (priced ? 'Pro · $price' : 'purchase status'),
                  onTap: !paid && priced ? _openProPurchase : null,
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
          const SizedBox(height: 8),
          HostGroupTray(
            label: 'Support',
            child: Column(
              children: [
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Help & FAQ',
                  meta: 'common questions',
                  onTap: _openHelp,
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Privacy',
                  meta: 'tursinalabs.com',
                  onTap: () => _openSupportUrl(kKelolaPrivacyUrl),
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Terms of Service',
                  meta: 'tursinalabs.com',
                  onTap: () => _openSupportUrl(kKelolaTermsUrl),
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Rate & review',
                  meta: 'Play Store',
                  onTap: () => _openSupportUrl(kKelolaPlayStoreUrl),
                ),
                const SizedBox(height: 8),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Share Kelola',
                  meta: 'invite a friend',
                  onTap: _shareKelola,
                ),
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
