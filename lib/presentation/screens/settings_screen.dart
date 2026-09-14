import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';

/// Paid only when unlock says so. The build token (`std` / `ext`) is not this.
/// Fleet unlimited stands in for the unlock set: tunnels has a single
/// production read on the host dashboard.
bool entitlementIsPaid(Entitlement entitlement) {
  return entitlement.isUnlocked(ProFeature.fleetUnlimited);
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _restoreNote;

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
    final c = context.kc;
    final entitlement = ref.watch(entitlementProvider);
    final paid = entitlementIsPaid(entitlement);
    return Scaffold(
      backgroundColor: c.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: HostsChromeAccent()),
          Column(
            children: [
              AppBar(
                backgroundColor: c.ink.withValues(alpha: 0),
                surfaceTintColor: c.ink.withValues(alpha: 0),
                foregroundColor: c.text,
                elevation: 0,
                scrolledUnderElevation: 0,
                forceMaterialTransparency: true,
                leading: const KelolaBackButton(),
                title: Text(
                  'Settings',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                shape: Border(bottom: BorderSide(color: c.line)),
              ),
              Expanded(
                child: ListView(
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
                            meta:
                                '$kelolaAppVersion · build $kelolaVersionCode',
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
                    const SizedBox(height: 8),
                    const HostGroupTray(
                      label: 'Appearance',
                      child: Column(
                        children: [
                          ServiceRow(
                            risk: RiskLevel.read,
                            name: 'Language',
                            meta: 'Not in this version',
                          ),
                          SizedBox(height: 8),
                          ServiceRow(
                            risk: RiskLevel.read,
                            name: 'Theme',
                            meta: 'Not in this version',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
