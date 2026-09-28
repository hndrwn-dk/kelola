import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/jump_chain.dart';
import 'package:kelola/presentation/screens/enrollment_screen.dart';
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
  String? _aliasError;
  String? _addressError;
  String? _userError;
  String? _formError;
  List<Host> _others = const [];
  String? _jumpHostId;

  @override
  void initState() {
    super.initState();
    _loadOthers();
  }

  bool _jumpWouldBeTooLong(String jumpId) {
    const placeholder = Host(
      id: '_new',
      alias: 'new',
      address: '0.0.0.0',
      port: 22,
      username: 'ops',
      keyAlias: 'kelola',
    );
    return resolveProposedJump(
          placeholder,
          jumpId,
          {for (final h in _others) h.id: h},
        ).kind ==
        JumpChainKind.tooLong;
  }

  Future<void> _loadOthers() async {
    final all = await ref.read(hostRepositoryProvider).list();
    if (!mounted) {
      return;
    }
    setState(() => _others = all);
  }

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
    final aliasError = alias.isEmpty ? 'Name is required.' : null;
    final addressError = address.isEmpty ? 'Address is required.' : null;
    String? userError;
    if (user.isEmpty) {
      userError = 'User is required.';
    } else if (user == 'root') {
      userError = 'Kelola does not log in as root. Use a sudoer.';
    }
    if (aliasError != null || addressError != null || userError != null) {
      setState(() {
        _aliasError = aliasError;
        _addressError = addressError;
        _userError = userError;
        _formError = null;
      });
      return;
    }
    setState(() {
      _aliasError = null;
      _addressError = null;
      _userError = null;
      _formError = null;
    });
    final host = await ref.read(hostRepositoryProvider).insert(
          alias: alias,
          address: address,
          port: port,
          username: user,
          jumpHostId: _jumpHostId,
        );
    await ref.read(enrollmentProvider.notifier).ensureKey();
    if (!mounted) {
      return;
    }
    final byId = {
      for (final h in await ref.read(hostRepositoryProvider).list()) h.id: h,
    };
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EnrollmentScreen(
          hostId: host.id,
          hostAlias: host.alias,
          jumpVia: jumpViaLabel(host, byId),
        ),
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
      if (n == 0) {
        setState(() {
          _formError = 'No hosts found in that config.';
        });
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = 'Could not import that config.';
      });
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return KelolaPage(
      title: 'Add host',
      kicker: 'SSH ONLY · NO AGENT',
      body: ListView(
        padding: kelolaScrollPadding(
          context,
          left: 16,
          top: 16,
          right: 16,
          extraBottom: 16,
        ),
        children: [
          if (_formError != null) ...[
            KelolaError(message: _formError!),
            const SizedBox(height: 14),
          ],
          KelolaField(
            key: const Key('add-host-alias'),
            label: 'Name',
            controller: _alias,
            hint: 'nas-01',
            error: _aliasError,
          ),
          const SizedBox(height: 14),
          KelolaField(
            key: const Key('add-host-address'),
            label: 'Address',
            controller: _address,
            hint: '192.168.1.24',
            keyboardType: TextInputType.url,
            error: _addressError,
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
                  key: const Key('add-host-user'),
                  label: 'User',
                  controller: _user,
                  hint: 'not root',
                  error: _userError,
                ),
              ),
            ],
          ),
          if (_others.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Jump host',
              style: KelolaType.body(color: c.muted, size: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                FilterPill(
                  label: 'None',
                  selected: _jumpHostId == null,
                  onTap: () => setState(() => _jumpHostId = null),
                ),
                for (final other in _others)
                  FilterPill(
                    label: other.alias,
                    selected: _jumpHostId == other.id,
                    enabled: !_jumpWouldBeTooLong(other.id),
                    onTap: () => setState(() => _jumpHostId = other.id),
                  ),
              ],
            ),
          ],
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
            style: KelolaType.body(color: c.dim, size: 12),
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
