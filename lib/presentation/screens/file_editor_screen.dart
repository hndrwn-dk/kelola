import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/files/sftp_lockout.dart';
import 'package:kelola/domain/files/sftp_path.dart';
import 'package:kelola/domain/files/text_diff.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_file_action.dart';
import 'package:kelola/providers.dart';

class FileEditorScreen extends ConsumerStatefulWidget {
  const FileEditorScreen({
    super.key,
    required this.hostId,
    required this.remotePath,
    required this.originalFile,
    required this.initialText,
  });

  final String hostId;
  final String remotePath;
  final File originalFile;
  final String initialText;

  @override
  ConsumerState<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends ConsumerState<FileEditorScreen> {
  late final TextEditingController _ctrl;
  Host? _host;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _loadHost();
  }

  Future<void> _loadHost() async {
    final host = await ref.read(hostRepositoryProvider).get(widget.hostId);
    if (mounted) {
      setState(() => _host = host);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final readOnly = _host?.readOnly ?? false;
    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sftpBasename(widget.remotePath),
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              widget.remotePath,
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
            ),
          ],
        ),
        actions: [
          if (!readOnly)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(
                'Save',
                style: KelolaType.display(color: c.amber, size: 13),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_saving)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: KelolaError(message: _error!, sudoUser: _host?.username),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                style: KelolaType.mono(color: c.text, size: 12),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surface,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: c.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.amber),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final host = _host;
    if (host == null) {
      return;
    }
    final edited = _ctrl.text;
    final original = await widget.originalFile.readAsString();
    if (!mounted) {
      return;
    }
    final diff = unifiedDiff(original, edited, path: widget.remotePath);
    if (diff.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final reviewed = await confirmFileDiff(context, diff);
    if (!reviewed || !mounted) {
      return;
    }
    if (isSshLockoutPath(widget.remotePath)) {
      final locked = await confirmFileMutate(
        context,
        hostAlias: host.alias,
        path: widget.remotePath,
        title: 'Save ${sftpBasename(widget.remotePath)}?',
        body: 'Uploads the edited file and writes a .bak first.',
        confirmLabel: 'Save',
      );
      if (!locked || !mounted) {
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final editedFile = File('${widget.originalFile.path}.edit');
      await editedFile.writeAsBytes(utf8.encode(edited), flush: true);
      if (!mounted) {
        return;
      }
      await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: SftpSaveProbe(
          remotePath: widget.remotePath,
          originalLocalPath: widget.originalFile.path,
          editedLocalPath: editedFile.path,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on SaveAbortedException {
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
