import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/screens/add_host_screen.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/search_screen.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/host_card.dart';
import 'package:kelola/providers.dart';

class HostsScreen extends ConsumerWidget {
  const HostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final hosts = ref.watch(hostsProvider);
    final recents = ref.watch(recentsProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AuditScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AddHostScreen()),
              );
              ref.invalidate(hostsProvider);
              ref.invalidate(recentsProvider);
            },
          ),
        ],
      ),
      body: hosts.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Add your first server. You'll need SSH access and a minute.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AddHostScreen(),
                          ),
                        );
                      },
                      child: const Text('Add host'),
                    ),
                  ],
                ),
              ),
            );
          }
          final recentIds = recents.map((h) => h.id).toSet();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(hostsProvider);
              ref.invalidate(recentsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (recents.isNotEmpty) ...[
                  Text(
                    'Recent',
                    style: TextStyle(color: colors.dim, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final h in recents)
                        ActionChip(
                          label: Text(h.alias),
                          onPressed: () => _openHost(context, ref, h),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                for (final host in list)
                  HostCard(
                    host: host,
                    onTap: () => _openHost(context, ref, host),
                  ),
                if (recentIds.isNotEmpty) const SizedBox(height: 8),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  Future<void> _openHost(BuildContext context, WidgetRef ref, Host host) async {
    await ref.read(hostRepositoryProvider).setLastHost(host.id);
    await ref.read(hostRepositoryProvider).touchRecent(host);
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostDashboardScreen(hostId: host.id),
      ),
    );
    ref.invalidate(hostsProvider);
    ref.invalidate(recentsProvider);
  }
}
