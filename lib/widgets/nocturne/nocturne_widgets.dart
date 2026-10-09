import 'package:flutter/material.dart';

import '../../models/task_priority.dart';
import '../../theme/nocturne_theme.dart';
import '../panel/panel.dart';

/// Three button voices: `primary` (a keycap with a lit accent edge),
/// `secondary` (a plain keycap), `ghost` (printed legend, no key).
enum NocturneButtonVariant { primary, secondary, ghost }

/// An icon+label keycap. It travels 2px down while pressed.
class NocturneButton extends StatefulWidget {
  const NocturneButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = NocturneButtonVariant.secondary,
    this.color,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NocturneButtonVariant variant;

  /// Overrides the accent color this button uses (e.g. a project's own
  /// color for its "New task" button). Defaults to the theme's accent.
  final Color? color;
  final bool dense;

  @override
  State<NocturneButton> createState() => _NocturneButtonState();
}

class _NocturneButtonState extends State<NocturneButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = widget.color ?? context.nocturneAccent;
    final ghost = widget.variant == NocturneButtonVariant.ghost;
    final primary = widget.variant == NocturneButtonVariant.primary;
    // On enamel, a pale accent (e.g. a pink project colour) is darkened for
    // the label only; the key's edge and tint keep the true colour.
    final fg = (ghost || primary)
        ? (tokens.isDark ? accent : Color.lerp(accent, Colors.black, 0.45)!)
        : tokens.text;
    final radius = BorderRadius.circular(NocturneRadius.md);

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Text(
          widget.label,
          style: TextStyle(
            color: fg,
            fontSize: widget.dense ? 14 : 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    Widget body = InkWell(
      onTap: widget.onPressed,
      onHighlightChanged: (v) => setState(() => _down = v),
      borderRadius: radius,
      hoverColor: context.nocturneHoverColor,
      splashColor: context.nocturneSplashColor,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.dense ? 10 : 12,
          vertical: widget.dense ? 6 : 8,
        ),
        child: child,
      ),
    );

    if (ghost) {
      body = Material(type: MaterialType.transparency, child: body);
    } else {
      var decoration = panelDecoration(
        context,
        depth: _down ? PanelDepth.recessed : PanelDepth.raised,
        fill: (!_down && primary)
            ? Color.lerp(tokens.surface, accent, tokens.isDark ? 0.18 : 0.14)
            : null,
      );
      if (primary) {
        decoration = decoration.copyWith(
          border: Border.all(color: accent.withValues(alpha: 0.8)),
        );
      }
      body = AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
        decoration: decoration,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          child: body,
        ),
      );
    }

    return Opacity(opacity: widget.onPressed == null ? 0.5 : 1, child: body);
  }
}

/// A small stamped label — used for priority tags (`.tag` + priority
/// colors) and generic outline/neutral tags (due dates, etc).
class NocturneTag extends StatelessWidget {
  const NocturneTag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.outline = false,
  });

  /// Builds the High/Med/Low priority tag with its fixed color, or null for
  /// [TaskPriority.none] (nothing to show).
  static Widget? forPriority(TaskPriority priority) {
    final color = switch (priority) {
      TaskPriority.high => NocturnePriority.high,
      TaskPriority.med => NocturnePriority.med,
      TaskPriority.low => NocturnePriority.low,
      TaskPriority.none => null,
    };
    if (color == null) return null;
    return NocturneTag(label: priority.label, color: color);
  }

  final String label;
  final IconData? icon;

  /// Fill/text color for a solid tag, or the fg/border color for an
  /// [outline] one (which otherwise defaults to the Appearance accent).
  final Color? color;

  /// An outlined tag (e.g. the due-date chip) instead of a filled one.
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final accent = context.nocturneAccent;
    final tokens = context.nocturne;

    final Color fg;
    final Color? bg;
    final Color borderColor;
    if (outline) {
      fg = color ?? accent;
      bg = null;
      borderColor = color ?? accent;
    } else if (color != null) {
      // Status hues stay legible on enamel by darkening the text only.
      fg = tokens.isDark ? color! : Color.lerp(color!, Colors.black, 0.5)!;
      bg = color!.withValues(alpha: 0.22);
      borderColor = color!.withValues(alpha: 0.55);
    } else {
      fg = tokens.neutral200;
      bg = tokens.neutral800;
      borderColor = tokens.edge;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(NocturneRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: fg,
              fontFamily: kPanelFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of mutually-exclusive options in one recessed housing; the
/// selected option is a keycap standing proud of it (view toggle,
/// priority/date-format/landing pickers).
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
      decoration: panelDecoration(context, depth: PanelDepth.recessed),
      child: Padding(
        padding: const EdgeInsets.all(2),
        // A SingleChildScrollView rather than a bare Row: with enough
        // options (or a narrow enough container — the Settings screen's
        // responsive columns can get quite tight), a fixed-width Row of
        // segments can ask for more space than it's given, which would
        // otherwise be a hard overflow error rather than something a user
        // ever notices.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < options.length; i++)
                DecoratedBox(
                  decoration: value == options[i]
                      ? panelDecoration(
                          context,
                          radius: NocturneRadius.sm + 1,
                          fill: Color.lerp(
                            tokens.surface,
                            accent,
                            tokens.isDark ? 0.45 : 0.35,
                          ),
                        )
                      : const BoxDecoration(),
                  child: InkWell(
                    onTap: () => onChanged(options[i]),
                    borderRadius: BorderRadius.circular(NocturneRadius.sm),
                    hoverColor: context.nocturneHoverColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (iconBuilder != null)
                            Icon(
                              iconBuilder!(options[i]),
                              size: 15,
                              color: tokens.text,
                            ),
                          if (labelBuilder != null)
                            Text(
                              labelBuilder!(options[i]),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: value == options[i]
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: tokens.text,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An engraved uppercase section header, e.g. "PROJECTS" / "FAVORITES".
class NocturneSectionLabel extends StatelessWidget {
  const NocturneSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(0, 0, 0, 12),
  });

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: StampLabel(text));
  }
}
