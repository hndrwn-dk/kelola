import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/providers.dart';

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key, this.hostId});

  final String? hostId;

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  List<AuditEvent> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(hostRepositoryProvider).listAudit(
          hostId: widget.hostId,
        );
    if (mounted) {
      setState(() => _rows = rows);
    }
  }

  Future<void> _copyJson() async {
    final payload = jsonEncode(
      _rows
          .map(
            (e) => {
              'id': e.id,
              'ts': e.timestampUtc.toIso8601String(),
              'host': e.hostAlias,
              'user': e.remoteUser,
              'command': e.command,
              'risk': e.risk,
              'sudo': e.usedSudo,
              'exit': e.exitCode,
              'ms': e.durationMs,
              'error': e.errorSummary,
            },
          )
          .toList(),
    );
    await Clipboard.setData(ClipboardData(text: payload));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _rows.isEmpty ? null : _copyJson,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _rows.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No commands recorded yet.',
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final e = _rows[i];
                  final color = e.orphan
                      ? colors.amber
                      : (e.exitCode != null && e.exitCode != 0) ||
                              e.errorSummary != null
                          ? colors.red
                          : colors.dim;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            e.timestampUtc.toIso8601String(),
                            e.hostAlias,
                            e.risk,
                            if (e.usedSudo) 'sudo',
                            if (e.orphan) 'interrupted',
                            if (e.exitCode != null) 'exit ${e.exitCode}',
                            '${e.durationMs}ms',
                          ].join(' · '),
                          style: TextStyle(color: color, fontSize: 11),
                        ),
                        SelectableText(
                          e.command,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        if (e.errorSummary != null)
                          Text(
                            e.errorSummary!,
                            style: TextStyle(color: colors.red, fontSize: 12),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
