import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/presentation/screens/enrollment_screen.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add host')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          TextField(
            controller: _alias,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'User'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: const Text('Next — add the key'),
          ),
          const SizedBox(height: 28),
          const Text('Import ssh_config instead'),
          const SizedBox(height: 8),
          TextField(
            controller: _config,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Paste Host blocks. IdentityFile is ignored.',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _importing ? null : _import,
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}
