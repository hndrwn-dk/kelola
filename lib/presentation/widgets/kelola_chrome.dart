import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

class KelolaBar extends StatelessWidget implements PreferredSizeWidget {
  const KelolaBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.titleWidget,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? titleWidget;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 52 : 60);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final canPop = Navigator.of(context).canPop();
    return ColoredBox(
      color: colors.ink,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: preferredSize.height,
          padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.line)),
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else if (canPop)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                )
              else
                const SizedBox(width: 10),
              Expanded(
                child: titleWidget ??
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: KelolaFonts.title(size: 17),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: KelolaFonts.eyebrow(colors),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
              ),
              ...?actions,
            ],
          ),
        ),
      ),
    );
  }
}

class KelolaPage extends StatelessWidget {
  const KelolaPage({
    super.key,
    required this.title,
    required this.body,
    this.kicker,
    this.kickerWidget,
    this.actions,
    this.leading,
    this.top,
    this.busy = false,
    this.fab,
  });

  final String title;
  final String? kicker;
  final Widget? kickerWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? top;
  final bool busy;
  final Widget? fab;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      floatingActionButton: fab,
      appBar: AppBar(
        leading: leading ??
            (canPop
                ? IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null),
        automaticallyImplyLeading: leading == null && canPop,
        title: kicker == null && kickerWidget == null
            ? Text(title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  kickerWidget ??
                      Text(kicker!, style: KelolaFonts.eyebrow(colors)),
                  Text(
                    title,
                    style: KelolaFonts.title(size: 17),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: actions,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?top,
          if (busy) const KelolaBusy(),
          Expanded(
            child: SafeArea(
              top: false,
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

class KelolaMasthead extends StatelessWidget {
  const KelolaMasthead({
    super.key,
    required this.title,
    this.kicker = 'KELOLA',
    this.actions = const [],
  });

  final String title;
  final String kicker;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return ColoredBox(
      color: colors.ink,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kicker, style: KelolaFonts.eyebrow(colors)),
                    const SizedBox(height: 4),
                    Text(title, style: KelolaFonts.title(size: 28)),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class KelolaTextAction extends StatelessWidget {
  const KelolaTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.accent = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool accent;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        label,
        style: KelolaFonts.machine(
          color: accent ? colors.amber : colors.muted,
          size: 11,
          weight: FontWeight.w500,
        ).copyWith(letterSpacing: 0.12),
      ),
    );
    if (onPressed == null) {
      if (tooltip == null) {
        return child;
      }
      return Tooltip(message: tooltip!, child: child);
    }
    final button = GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class KelolaIconButton extends StatelessWidget {
  const KelolaIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return IconButton(
      icon: Icon(icon, size: 20, color: color ?? colors.muted),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
  }
}

class KelolaPanel extends StatelessWidget {
  const KelolaPanel({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(12, 11, 12, 11),
    this.accent,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final body = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accent != null)
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
            Expanded(child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return body;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: body,
      ),
    );
  }
}

class KelolaWorkLine extends StatelessWidget {
  const KelolaWorkLine({
    super.key,
    required this.title,
    this.onTap,
    this.alert = false,
  });

  final String title;
  final VoidCallback? onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.line)),
          ),
          child: Text(
            title,
            style: KelolaFonts.title(
              size: 15,
              color: alert ? colors.amber : colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class KelolaNumStrip extends StatelessWidget {
  const KelolaNumStrip({super.key, required this.items});

  final List<(String label, String value, VoidCallback? onTap)> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: items[i].$3,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[i].$1,
                    style: KelolaFonts.eyebrow(colors),
                  ),
                  const SizedBox(height: 4),
                  Text(items[i].$2, style: KelolaFonts.title(size: 24)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class KelolaWorkRow extends StatelessWidget {
  const KelolaWorkRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (accent != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KelolaFonts.title(size: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KelolaFonts.machine(color: colors.dim, size: 11),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
    final lined = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: row,
    );
    if (onTap == null) {
      return lined;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: lined),
    );
  }
}

class KelolaSeg extends StatelessWidget {
  const KelolaSeg({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            ChoiceChip(
              label: Text(labels[i]),
              selected: i == index,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              selectedColor: colors.amber.withValues(alpha: 0.18),
              backgroundColor: colors.surface2,
              side: BorderSide(
                color: i == index
                    ? colors.amber.withValues(alpha: 0.55)
                    : colors.line,
              ),
              labelStyle: KelolaFonts.machine(
                color: i == index ? colors.amber : colors.muted,
                size: 11,
                weight: FontWeight.w500,
              ),
              onSelected: (_) => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class KelolaField extends StatelessWidget {
  const KelolaField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int? minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: KelolaFonts.machine(color: colors.dim, size: 10)
              .copyWith(letterSpacing: 0.12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          autofocus: autofocus,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: KelolaFonts.machine(size: 14, color: colors.text),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class KelolaEmpty extends StatelessWidget {
  const KelolaEmpty({
    super.key,
    required this.body,
    this.title,
    this.action,
  });

  final String body;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KelolaMark(size: 36),
          if (title != null) ...[
            const SizedBox(height: 16),
            Text(
              title!,
              style: KelolaFonts.title(size: 22),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted, height: 1.55, fontSize: 14),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

class KelolaMark extends StatelessWidget {
  const KelolaMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final h = size * 0.14;
    return SizedBox(
      width: size,
      height: size * 0.72,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: size * 0.08,
            child: _bar(colors.surface2, size * 0.62, h),
          ),
          Positioned(
            left: 0,
            top: size * 0.32,
            child: _bar(colors.amber, size * 0.78, h),
          ),
          Positioned(
            left: 0,
            top: size * 0.56,
            child: _bar(colors.surface2, size * 0.48, h),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: size * 0.14,
              height: size * 0.14,
              decoration: BoxDecoration(
                color: colors.amber,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(Color color, double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(h),
      ),
    );
  }
}

class KelolaPill extends StatelessWidget {
  const KelolaPill({
    super.key,
    required this.label,
    required this.color,
    this.border,
  });

  final String label;
  final Color color;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border ?? color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        style: KelolaFonts.machine(
          color: color,
          size: 9,
          weight: FontWeight.w500,
        ).copyWith(letterSpacing: 0.08),
      ),
    );
  }
}

class KelolaBusy extends StatelessWidget {
  const KelolaBusy({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return LinearProgressIndicator(
      minHeight: 1.5,
      backgroundColor: colors.surface,
      color: colors.amber,
    );
  }
}

class KelolaSpinner extends StatelessWidget {
  const KelolaSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 1.6,
        color: colors.amber,
      ),
    );
  }
}

class KelolaChip extends StatelessWidget {
  const KelolaChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: colors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 3, color: colors.amber.withValues(alpha: 0.7)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
                child: Text(label, style: KelolaFonts.title(size: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KelolaSection extends StatelessWidget {
  const KelolaSection(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Text(label.toUpperCase(), style: KelolaFonts.eyebrow(colors));
  }
}

class KelolaCommand extends StatelessWidget {
  const KelolaCommand({super.key, required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: KelolaFonts.machine(size: 12, color: colors.text),
            ),
          ),
          KelolaIconButton(
            icon: Icons.copy,
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
            },
          ),
        ],
      ),
    );
  }
}
