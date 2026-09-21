import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

class AppLockScreen extends StatelessWidget {
  const AppLockScreen({
    super.key,
    required this.onUnlock,
    this.notice,
  });

  final VoidCallback onUnlock;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return KelolaWashScaffold(
      appBar: AppBar(
        backgroundColor: c.ink.withValues(alpha: 0),
        surfaceTintColor: c.ink.withValues(alpha: 0),
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        title: Text(
          'Kelola',
          style: KelolaType.display(color: c.text, size: 16),
        ),
        shape: Border(bottom: BorderSide(color: c.line)),
      ),
      body: ListView(
        padding: kelolaScrollPadding(
          context,
          left: 16,
          top: 24,
          right: 16,
        ),
        children: [
          Text(
            'Unlock to open the inventory',
            style: KelolaType.body(color: c.muted, size: 14),
          ),
          const SizedBox(height: 24),
          KelolaPrimaryButton(label: 'Unlock', onTap: onUnlock),
          if (notice != null) ...[
            const SizedBox(height: 16),
            Text(
              notice!,
              style: KelolaType.body(color: c.muted, size: 13),
            ),
          ],
        ],
      ),
    );
  }
}
