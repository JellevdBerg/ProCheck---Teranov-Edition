import 'package:flutter/material.dart';

import 'nocturne_theme.dart';

/// Shadow tokens for the Industrial Skeuomorphism redesign — every "level"
/// in the elevation model (see the design brief in
/// `/mnt/project-files/design/industrial-skeuomorphism-flutter-prompt.md`)
/// maps to one of these, derived from each brightness's own [NocturneColors]
/// rather than a hardcoded hex, since Nocturne is dark-first.

/// Panel level (cards, dialogs, the sidebar): a dual shadow — dark
/// bottom-right (the panel's own cast shadow) plus a faint light top-left
/// (the edge catching the scene's top-left light source) — is what reads as
/// "resting on" the chassis instead of painted flat onto it.
List<BoxShadow> panelShadow(NocturneColors t) => [
  BoxShadow(color: Colors.black.withValues(alpha: 0.35), offset: const Offset(6, 6), blurRadius: 14),
  BoxShadow(color: t.neutral100.withValues(alpha: 0.06), offset: const Offset(-4, -4), blurRadius: 10),
];

/// Floating level (buttons, menus, the accent sync pill): a stronger version
/// of [panelShadow] for elements that sit above panels.
List<BoxShadow> floatingShadow(NocturneColors t) => [
  BoxShadow(color: Colors.black.withValues(alpha: 0.45), offset: const Offset(8, 8), blurRadius: 20),
  BoxShadow(color: t.neutral100.withValues(alpha: 0.08), offset: const Offset(-6, -6), blurRadius: 16),
];

/// A colored glow — reserved for active/focused/selected indicators (a
/// status LED, a focused input's ring, a selected priority tag), never a
/// whole panel.
List<BoxShadow> glow(Color accent) => [
  BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 12, spreadRadius: 1),
];
