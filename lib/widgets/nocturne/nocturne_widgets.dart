import 'package:flutter/material.dart';

import '../../models/task_priority.dart';
import '../../theme/nocturne_theme.dart';
import '../panel/panel.dart';

/// Three button voices: `primary` (accent fill), `secondary` (outlined),
/// `ghost` (text only, hover wash).
enum NocturneButtonVariant { primary, secondary, ghost }

/// An icon+label button, 32px tall (28px when [dense]).
class NocturneButton extends StatelessWidget {
  const NocturneButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = NocturneButtonVariant.secondary,
    this.color,
    this.dense = false,
    this.minWidth,
  });

  /// Optional minimum width so sibling actions (New project / New task /
  /// New template) come out the same size.
  final double? minWidth;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NocturneButtonVariant variant;

  /// Overrides the accent color this button uses (e.g. a project's own
  /// color for its "New task" button). Defaults to the theme's accent.
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final brightness = Theme.of(context).brightness;
    final accent = color == null
        ? context.nocturneAccent
        : tuneAccent(color!, brightness);
    final primary = variant == NocturneButtonVariant.primary;
    final ghost = variant == NocturneButtonVariant.ghost;
    final onAccent = accent.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    final fg = primary ? onAccent : (ghost && color != null ? accent : tokens.text);
    final radius = BorderRadius.circular(NocturneRadius.md);

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              height: 20 / 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: primary
            ? accent
            : (ghost ? Colors.transparent : tokens.surface),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: (primary || ghost)
              ? BorderSide.none
              : BorderSide(color: tokens.borderStrong),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          hoverColor: primary
              ? Colors.white.withValues(alpha: 0.12)
              : tokens.raised,
          focusColor: accent.withValues(alpha: 0.2),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: dense ? 28 : 32,
              minWidth: minWidth ?? 0,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 8 : 12,
                vertical: dense ? 4 : 6,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small chip — priority, due date, or a generic label. Color is paired
/// with text (and a glyph for priority), never alone.
class NocturneTag extends StatelessWidget {
  const NocturneTag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.outline = false,
  });

  /// Builds the High/Med/Low priority tag with its fixed color and glyph,
  /// or null for [TaskPriority.none] (nothing to show).
  static Widget? forPriority(TaskPriority priority) {
    final (color, icon) = switch (priority) {
      TaskPriority.high => (NocturnePriority.high, Icons.keyboard_double_arrow_up),
      TaskPriority.med => (NocturnePriority.med, Icons.drag_handle),
      TaskPriority.low => (NocturnePriority.low, Icons.keyboard_arrow_down),
      TaskPriority.none => (null, null),
    };
    if (color == null) return null;
    return NocturneTag(label: priority.label, color: color, icon: icon);
  }

  final String label;
  final IconData? icon;

  /// Status hue for the chip. Null = neutral.
  final Color? color;

  /// A bordered chip with no fill instead of a tinted one.
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    // The fixed priority/status constants resolve to the theme's own tokens,
    // so a "medium" chip is the same orange as a due-soon bar or tile.
    final resolved = switch (color) {
      NocturnePriority.high => t.danger,
      NocturnePriority.med => t.warn,
      NocturnePriority.low => t.low,
      NocturneStatus.done => t.done,
      final c => c,
    };
    final Color fg;
    final Color? bg;
    final Color border;
    if (resolved != null) {
      fg = resolved;
      bg = outline ? null : resolved.withValues(alpha: t.isDark ? 0.16 : 0.12);
      border = outline ? resolved : Colors.transparent;
    } else {
      fg = t.neutral300;
      bg = outline ? null : t.neutral800;
      border = outline ? t.borderStrong : Colors.transparent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(NocturneRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 11.5,
                height: 16 / 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of mutually-exclusive options in one track; the selected option is
/// an accent-tinted segment (view toggle, priority/date-format/landing
/// pickers).
class NocturneSegmented<T> extends StatelessWidget {
  const NocturneSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelBuilder,
    this.iconBuilder,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelBuilder;
  final IconData Function(T)? iconBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.raised,
        border: Border.all(color: tokens.edge),
        borderRadius: BorderRadius.circular(NocturneRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        // Scrolls rather than overflows when a narrow container can't fit
        // every option.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < options.length; i++)
                _segment(context, tokens, accent, options[i]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    NocturneColors tokens,
    Color accent,
    T option,
  ) {
    final selected = value == option;
    final fg = selected ? accent : tokens.neutral300;
    return Material(
      color: selected
          ? accent.withValues(alpha: tokens.isDark ? 0.18 : 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(NocturneRadius.sm + 1),
      child: InkWell(
        onTap: () => onChanged(option),
        borderRadius: BorderRadius.circular(NocturneRadius.sm + 1),
        hoverColor: tokens.neutral800,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconBuilder != null)
                Icon(iconBuilder!(option), size: 15, color: fg),
              if (iconBuilder != null && labelBuilder != null)
                const SizedBox(width: 5),
              if (labelBuilder != null)
                Text(
                  labelBuilder!(option),
                  style: TextStyle(
                    fontSize: 13,
                    height: 20 / 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section header, e.g. "PROJECTS" / "FAVORITES".
class NocturneSectionLabel extends StatelessWidget {
  const NocturneSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(0, 0, 0, 8),
  });

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: StampLabel(text));
  }
}
