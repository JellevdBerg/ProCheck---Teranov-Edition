import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';

/// Multi-user cue chips (see `docs/DESIGN.md`). Restyles data the Admin and
/// Team screens already show; adds no new reads.
///
/// Vocabulary, used the same way everywhere:
/// - role: text chip — Manager filled, Member outlined
/// - department: hue dot + name; Operator / IT add a distinct glyph
/// - person: initials avatar
/// Colour is never the only carrier: every cue also has text or a glyph.

/// `Member` / `Manager` chip. Manager is filled and Member outlined, so the
/// difference does not depend on colour.
class RolePlate extends StatelessWidget {
  const RolePlate({super.key, required this.isManager});

  final bool isManager;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NocturneRadius.sm),
        color: isManager ? t.neutral800 : null,
        border: Border.all(color: isManager ? Colors.transparent : t.borderStrong),
      ),
      child: Text(
        isManager ? 'Manager' : 'Member',
        maxLines: 1,
        style: TextStyle(
          fontSize: 11.5,
          height: 16 / 11.5,
          fontWeight: isManager ? FontWeight.w600 : FontWeight.w500,
          color: isManager ? t.text : t.neutral400,
        ),
      ),
    );
  }
}

/// Department chip: a hue dot and the name. Operator and IT departments
/// (company-wide access) swap the dot for a glyph on a tinted chip.
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
    final hue = context.departmentColor(name);
    final special = isOperator || isIt;
    final lead = isOperator
        ? Icons.admin_panel_settings_outlined
        : (isIt ? Icons.terminal : null);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(special ? 10 : NocturneRadius.sm),
        color: special ? context.nocturneAccent.withValues(alpha: 0.12) : null,
        border: Border.all(color: special ? Colors.transparent : t.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lead != null)
            Icon(lead, size: 12, color: context.nocturneAccent)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 16 / 11.5,
                fontWeight: FontWeight.w500,
                color: special ? t.text : t.neutral300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Initials in a round avatar. [dashed] draws the empty "unassigned" state.
class AvatarWell extends StatelessWidget {
  const AvatarWell({
    super.key,
    required this.initial,
    this.size = 28,
    this.dashed = false,
  });

  final String initial;
  final double size;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dashed ? null : t.neutral800,
        border: dashed ? Border.all(color: t.borderStrong) : null,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: size * 0.42,
          color: t.neutral200,
        ),
      ),
    );
  }
}

/// A quiet inline notice for empty / error states.
class PanelNotice extends StatelessWidget {
  const PanelNotice(this.text, {super.key, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    final c = isError ? t.danger : t.neutral400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        color: isError ? t.danger.withValues(alpha: 0.08) : t.raised,
        border: Border.all(color: isError ? t.danger.withValues(alpha: 0.4) : t.edge),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: c,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: c))),
        ],
      ),
    );
  }
}
