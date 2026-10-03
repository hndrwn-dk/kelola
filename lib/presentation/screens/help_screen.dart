import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/support/support_links.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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
        leadingWidth: KelolaChromeIconButton.leadingWidth,
        leading: const Align(
          alignment: Alignment.center,
          child: KelolaBackButton(),
        ),
        titleSpacing: KelolaChromeIconButton.titleGap,
        title: Text(
          'Help',
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
          for (var i = 0; i < kSupportFaq.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            HelpTopic(
              question: kSupportFaq[i].question,
              answer: kSupportFaq[i].answer,
            ),
          ],
        ],
      ),
    );
  }
}
