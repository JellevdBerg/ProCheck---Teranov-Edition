import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';
import 'panel/panel.dart';

/// Multi-user cue plates (see `docs/DESIGN.md`). Restyles data the Admin and
/// Team screens already show; adds no new reads.

/// Engraved `MEMBER` / `MANAGER` plate. A manager's plate has a double rule
/// (an inner hairline), so the difference does not depend on colour.
class RolePlate extends StatelessWidget {
  const RolePlate({super.key, required this.isManager});

  final bool isManager;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    final label = StampLabel(
      isManager ? 'Manager' : 'Member',
      size: 11,
      color: isManager ? t.neutral300 : t.neutral500,
    );
    return DecoratedBox(
      decoration: panelDecoration(context, depth: PanelDepth.flat, radius: 3),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: isManager ? Border.all(color: t.edge) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: label,
          ),
        ),
      ),
    );
  }
}

/// Neutral stamped department name. Operator and IT departments (company-wide
/// access) get a different plate shape and a lit lamp, paired with the name.
class DepartmentPlate extends StatelessWidget {
  const DepartmentPlate({
    super.key,
    required this.name,
    this.isOperator = false,
    this.isIt = false,
  });

  final String name;
  final bool isOperator;
  final bool isIt;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    final wide = isOperator || isIt;
    return DecoratedBox(
      decoration: panelDecoration(
        context,
        depth: wide ? PanelDepth.raised : PanelDepth.flat,
        radius: wide ? 10 : 3,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 8 : 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wide) ...[
              IndicatorLamp(on: true, color: context.nocturneAccent, size: 8),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kPanelFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 1.0,
                  color: wide ? t.text : t.neutral400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Initial badge sunk into a recessed well.
class AvatarWell extends StatelessWidget {
  const AvatarWell({super.key, required this.initial, this.size = 32});

  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: panelDecoration(
        context,
        depth: PanelDepth.recessed,
        radius: size / 2,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: kPanelFont,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.5,
          color: t.neutral200,
        ),
      ),
    );
  }
}

/// A recessed readout used for loading-free notices (empty / error states).
class PanelNotice extends StatelessWidget {
  const PanelNotice(this.text, {super.key, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return DecoratedBox(
      decoration: panelDecoration(context, depth: PanelDepth.recessed),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          text,
          style: TextStyle(
            color: isError ? Theme.of(context).colorScheme.error : t.neutral400,
          ),
        ),
      ),
    );
  }
}
