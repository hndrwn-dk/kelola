import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/chmod_mode.dart';
import 'package:kelola/domain/files/file_edit_save.dart';
import 'package:kelola/domain/files/sftp_entry.dart';
import 'package:kelola/domain/files/sftp_format.dart';
import 'package:kelola/domain/files/sftp_list_view.dart';
import 'package:kelola/domain/files/sftp_path.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/file_editor_screen.dart';
import 'package:kelola/presentation/widgets/confirm_file_action.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';
import 'package:path_provider/path_provider.dart';

class _Transfer {
  _Transfer({required this.label});

  final String label;
  int done = 0;
  int? total;
  TransferCancel cancel = TransferCancel();

  double get fraction {
    final t = total;
    if (t == null || t <= 0) {
      return 0;
    }
    return (done / t).clamp(0.0, 1.0);
  }

  String get detail {
    final t = total;
    if (t == null) {
      return formatSftpSize(done);
    }
    return '${formatSftpSize(done)} / ${formatSftpSize(t)}';
  }
}

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, required this.hostId, this.initialPath = '.'});

  final String hostId;
  final String initialPath;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  Host? _host;
  HostFacts? _facts;
  String _path = '.';
  List<SftpEntry> _entries = const [];
  String? _error;
  bool _loading = true;
  bool _showHidden = false;
  _Transfer? _transfer;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final host = await ref.read(hostRepositoryProvider).get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final listing = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: SftpListProbe(path: _path),
        facts: _facts,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _host = host;
        _path = listing.path;
        _entries = listing.entries;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<T?> _run<T>(SftpProbe<T> probe, {TransferCancel? cancel, void Function(int, int?)? onProgress}) async {
    final host = _host;
    if (host == null || !mounted) {
      return null;
    }
    try {
      return await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: probe,
        facts: _facts,
        cancel: cancel,
        onProgress: onProgress,
      );
    } on TransferCancelledException {
      return null;
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
      return null;
    }
  }

  Future<Directory> _transferDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/kelola-transfers');
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final view = SftpListView.build(_entries, showHidden: _showHidden);
    final readOnly = _host?.readOnly ?? false;
    final transfer = _transfer;

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Files', style: KelolaType.display(color: c.text, size: 16)),
            Text(
              _path,
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Parent directory',
            onPressed: _path == '/' ? null : () {
              _path = sftpParent(_path);
              _load();
            },
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
          if (!readOnly)
            IconButton(
              tooltip: 'New directory',
              onPressed: _mkdir,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          if (!readOnly)
            IconButton(
              tooltip: 'Upload',
              onPressed: _upload,
              icon: const Icon(Icons.upload_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                FilterPill(
                  label: 'HIDDEN ${view.hiddenCount}',
                  selected: _showHidden,
                  onTap: () => setState(() => _showHidden = !_showHidden),
                ),
              ],
            ),
          ),
          if (transfer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: RiskBand(
                risk: RiskLevel.read,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      transfer.label,
                      style: KelolaType.display(color: c.text, size: 13),
                    ),
                    const SizedBox(height: 6),
                    StatCard(
                      label: 'TRANSFER',
                      value: '${(transfer.fraction * 100).round()}',
                      unit: '%',
                      meterFraction: transfer.fraction,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      transfer.detail,
                      style: KelolaType.mono(color: c.muted, size: 11),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => transfer.cancel.cancel(),
                        child: Text(
                          'Cancel',
                          style: KelolaType.display(color: c.amber, size: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: KelolaError(message: _error!, sudoUser: _host?.username),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: view.rows.isEmpty && !_loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        KelolaEmpty(body: view.emptyCopy ?? 'This directory is empty.'),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: kelolaScrollPadding(context),
                      itemCount: view.rows.length,
                      itemBuilder: (context, i) {
                        final e = view.rows[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ServiceRow(
                            risk: RiskLevel.read,
                            name: e.name,
                            meta: sftpRowMeta(
                              permissions: e.permissions,
                              owner: e.owner,
                              size: e.size,
                              mtime: e.mtime,
                              isDirectory: e.isDirectory,
                            ),
                            onTap: () => _open(e),
                            onLongPress: () => _actions(e),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(SftpEntry e) async {
    if (e.isDirectory) {
      _path = e.path;
      await _load();
      return;
    }
    await _edit(e);
  }

  Future<void> _actions(SftpEntry e) async {
    final host = _host;
    if (host == null) {
      return;
    }
    final readOnly = host.readOnly;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return KelolaSheet(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!e.isDirectory)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ServiceRow(
                      risk: RiskLevel.read,
                      name: 'View / edit',
                      meta: 'text files only',
                      onTap: () {
                        Navigator.pop(ctx);
                        _edit(e);
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ServiceRow(
                    risk: RiskLevel.read,
                    name: 'Download',
                    meta: 'stream to this device',
                    onTap: () {
                      Navigator.pop(ctx);
                      _download(e);
                    },
                  ),
                ),
                if (!readOnly) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ServiceRow(
                      risk: RiskLevel.mutate,
                      name: 'Rename',
                      meta: e.name,
                      onTap: () {
                        Navigator.pop(ctx);
                        _rename(e);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ServiceRow(
                      risk: RiskLevel.mutate,
                      name: 'chmod',
                      meta: e.permissions,
                      onTap: () {
                        Navigator.pop(ctx);
                        _chmod(e);
                      },
                    ),
                  ),
                  ServiceRow(
                    risk: RiskLevel.destructive,
                    name: 'Delete',
                    meta: e.name,
                    onTap: () {
                      Navigator.pop(ctx);
                      _delete(e);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _edit(SftpEntry e) async {
    final host = _host;
    if (host == null) {
      return;
    }
    final dir = await Directory.systemTemp.createTemp('kelola-edit');
    final local = File('${dir.path}/${e.name}');
    final xfer = _Transfer(label: 'Download ${e.name}');
    setState(() => _transfer = xfer);
    final bytes = await _run(
      SftpDownloadProbe(remotePath: e.path, localPath: local.path),
      cancel: xfer.cancel,
      onProgress: (done, total) {
        if (!mounted) {
          return;
        }
        setState(() {
          xfer.done = done;
          xfer.total = total;
        });
      },
    );
    if (!mounted) {
      return;
    }
    setState(() => _transfer = null);
    if (bytes == null || !local.existsSync()) {
      return;
    }
    try {
      final raf = await local.open();
      final peek = await raf.read(8192);
      final size = await raf.length();
      await raf.close();
      guardTextEdit(peek: peek, size: size);
      final text = await local.readAsString();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FileEditorScreen(
            hostId: host.id,
            remotePath: e.path,
            originalFile: local,
            initialText: text,
          ),
        ),
      );
    } on BinaryFileException catch (err) {
      setState(() => _error = err.message);
    } on FileTooLargeToEditException catch (err) {
      setState(() => _error = err.message);
    } catch (err) {
      setState(() => _error = describeSshError(err));
    }
  }

  Future<void> _download(SftpEntry e) async {
    if (e.isDirectory) {
      setState(() => _error = 'Download a file, not a directory.');
      return;
    }
    final dest = File('${(await _transferDir()).path}/${e.name}');
    final xfer = _Transfer(label: 'Download ${e.name}');
    setState(() {
      _transfer = xfer;
      _error = null;
    });
    final n = await _run(
      SftpDownloadProbe(remotePath: e.path, localPath: dest.path),
      cancel: xfer.cancel,
      onProgress: (done, total) {
        if (!mounted) {
          return;
        }
        setState(() {
          xfer.done = done;
          xfer.total = total;
        });
      },
    );
    if (!mounted) {
      return;
    }
    setState(() => _transfer = null);
    if (n != null) {
      setState(() => _error = null);
      if (!mounted) {
        return;
      }
      final c = context.kc;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dest.path,
            style: KelolaType.mono(color: c.text, size: 11),
          ),
        ),
      );
    }
  }

  Future<void> _mkdir() async {
    final host = _host;
    if (host == null) {
      return;
    }
    final name = await _prompt(label: 'Directory name', confirmLabel: 'Create');
    if (name == null || name.trim().isEmpty || !mounted) {
      return;
    }
    final path = joinSftpPath(_path, name.trim());
    final ok = await confirmFileMutate(
      context,
      hostAlias: host.alias,
      path: path,
      title: 'Create $name?',
      body: 'Creates a directory on ${host.alias}.',
      confirmLabel: 'Create',
    );
    if (!ok) {
      return;
    }
    await _run(SftpMkdirProbe(path: path));
    await _load();
  }

  Future<void> _rename(SftpEntry e) async {
    final host = _host;
    if (host == null) {
      return;
    }
    final name = await _prompt(
      label: 'New name',
      initial: e.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name.trim().isEmpty || name.trim() == e.name || !mounted) {
      return;
    }
    final to = joinSftpPath(sftpParent(e.path), name.trim());
    final ok = await confirmFileMutate(
      context,
      hostAlias: host.alias,
      path: e.path,
      title: 'Rename ${e.name}?',
      body: 'Renames the object on ${host.alias}.',
      confirmLabel: 'Rename',
    );
    if (!ok) {
      return;
    }
    await _run(SftpRenameProbe(from: e.path, to: to));
    await _load();
  }

  Future<void> _chmod(SftpEntry e) async {
    final host = _host;
    if (host == null) {
      return;
    }
    final raw = await _prompt(
      label: 'Mode (octal)',
      initial: '644',
      confirmLabel: 'chmod',
      mono: true,
    );
    if (raw == null || !mounted) {
      return;
    }
    late final int mode;
    try {
      mode = parseOctalMode(raw);
    } on FormatException {
      setState(() => _error = 'Invalid mode');
      return;
    }
    final ok = await confirmFileMutate(
      context,
      hostAlias: host.alias,
      path: e.path,
      title: 'chmod ${e.name}?',
      body: 'Sets mode ${formatOctalMode(mode)} on ${host.alias}.',
      confirmLabel: 'chmod',
    );
    if (!ok) {
      return;
    }
    await _run(SftpChmodProbe(path: e.path, mode: mode));
    await _load();
  }

  Future<void> _delete(SftpEntry e) async {
    final host = _host;
    if (host == null) {
      return;
    }
    final ok = await confirmFileDelete(
      context,
      hostAlias: host.alias,
      path: e.path,
    );
    if (!ok) {
      return;
    }
    await _run(SftpDeleteProbe(path: e.path));
    await _load();
  }

  Future<void> _upload() async {
    final host = _host;
    if (host == null) {
      return;
    }
    final dir = await _transferDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .toList()
      ..sort((a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));
    if (!mounted) {
      return;
    }
    if (files.isEmpty) {
      setState(() {
        _error =
            'Nothing to upload. Download a file first; Kelola reads from kelola-transfers.';
      });
      return;
    }
    final chosen = await showModalBottomSheet<File>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return KelolaSheet(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in files)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ServiceRow(
                      risk: RiskLevel.mutate,
                      name: f.uri.pathSegments.last,
                      meta: f.path,
                      onTap: () => Navigator.pop(ctx, f),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) {
      return;
    }
    final name = chosen.uri.pathSegments.last;
    final remote = joinSftpPath(_path, name);
    final ok = await confirmFileMutate(
      context,
      hostAlias: host.alias,
      path: remote,
      title: 'Upload $name?',
      body: 'Writes $name into $_path on ${host.alias}.',
      confirmLabel: 'Upload',
    );
    if (!ok) {
      return;
    }
    final xfer = _Transfer(label: 'Upload $name');
    setState(() => _transfer = xfer);
    await _run(
      SftpUploadProbe(localPath: chosen.path, remotePath: remote),
      cancel: xfer.cancel,
      onProgress: (done, total) {
        if (!mounted) {
          return;
        }
        setState(() {
          xfer.done = done;
          xfer.total = total ?? chosen.lengthSync();
        });
      },
    );
    if (mounted) {
      setState(() => _transfer = null);
    }
    await _load();
  }

  Future<String?> _prompt({
    required String label,
    String? initial,
    required String confirmLabel,
    bool mono = false,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final c = context.kc;
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          child: RiskBand(
            risk: RiskLevel.mutate,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KelolaInput(
                  label: label,
                  controller: ctrl,
                  mono: mono,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: KelolaType.display(color: c.muted, size: 13),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text),
                        child: Text(
                          confirmLabel,
                          style: KelolaType.display(color: c.amber, size: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    return value;
  }
}
