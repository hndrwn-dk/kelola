import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/presentation/screens/enrollment_screen.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

class AddHostScreen extends ConsumerStatefulWidget {
  const AddHostScreen({super.key});

  @override
  ConsumerState<AddHostScreen> createState() => _AddHostScreenState();
}

class _AddHostScreenState extends ConsumerState<AddHostScreen> {
  final _alias = TextEditingController();
  final _address = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _config = TextEditingController();
  bool _importing = false;

  @override
  void dispose() {
    _alias.dispose();
    _address.dispose();
    _port.dispose();
    _user.dispose();
    _config.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final alias = _alias.text.trim();
    final address = _address.text.trim();
    final user = _user.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 22;
    if (alias.isEmpty || address.isEmpty || user.isEmpty) {
      return;
    }
    if (user == 'root') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kelola does not log in as root. Use a sudoer.',
          ),
        ),
      );
      return;
    }
    final host = await ref.read(hostRepositoryProvider).insert(
          alias: alias,
          address: address,
          port: port,
          username: user,
        );
    await ref.read(enrollmentProvider.notifier).ensureKey();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EnrollmentScreen(hostId: host.id),
      ),
    );
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final n = await ref
          .read(hostRepositoryProvider)
          .importSshConfig(_config.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $n hosts. IdentityFile ignored.')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return KelolaPage(
      title: 'Add host',
      kicker: 'SSH ONLY · NO AGENT',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          KelolaField(
            label: 'Name',
            controller: _alias,
            hint: 'nas-01',
          ),
          const SizedBox(height: 14),
          KelolaField(
            label: 'Address',
            controller: _address,
            hint: '192.168.1.24',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KelolaField(
                  label: 'Port',
                  controller: _port,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: KelolaField(
                  label: 'User',
                  controller: _user,
                  hint: 'not root',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Next — add the key'),
          ),
          const SizedBox(height: 32),
          const KelolaSection('Or import ssh_config'),
          const SizedBox(height: 6),
          Text(
            'Paste Host blocks. IdentityFile is ignored — this phone keeps one hardware key.',
            style: TextStyle(color: colors.dim, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 10),
          KelolaField(
            label: 'Config',
            controller: _config,
            minLines: 6,
            maxLines: 12,
            hint: 'Host nas-01\n  HostName 192.168.1.24\n  User hendr',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _importing ? null : _import,
            child: Text(_importing ? 'Importing…' : 'Import'),
          ),
        ],
      ),
    );
  }
}
