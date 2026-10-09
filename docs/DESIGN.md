# ProCheck industrial UI — design spec

Visual change only. Providers, models, data calls, callbacks and routes are
not touched. One design, two finishes: **graphite** (dark) and **enamel**
(light). Same geometry, bevels, lamps and type; only the material differs.
Follows the system setting by default; Settings → Appearance (System / Light /
Dark, persisted) is the override and already existed.

## Rules (read before touching a screen)
1. **Never hard-code colours.** Use `context.nocturne` (tokens), `context.nocturneAccent`, `NocturnePriority`, `NocturneStatus`. Token *names* are unchanged from the old theme (`neutral100..900`, `bg`, `surface`, `text`, `divider`); in dark the ramp runs light→dark with the number, in light it is inverted so roles stay the same. New roles: `well` (recessed), `hi`/`lo` (bevel light/shadow), `edge` (plate hairline), `isDark`.
2. **One light source, top-left.** Depth comes only from `panelDecoration(context, depth: raised | recessed | flat)`. Do not hand-roll box shadows.
   - *raised* = plates, keys, cards that hold content, the selected segment
   - *recessed* = inputs, readouts, switch housings, gauges, wells
   - *flat* = printed-on (dividers, table rows)
3. **Text sits on flat or recessed surfaces**, never on gradient texture. Body text is `Barlow` (400/500). Engraved labels, headings, tags are `BarlowCondensed` 600 (`kPanelFont`), uppercase, tracked — use `StampLabel`/`NocturneSectionLabel`/`NocturneTag`, never for sentences.
4. **Lamps never carry state alone** — pair with text, position or a switch.
5. **Motion is mechanical:** 60ms key travel, 160ms switch snap with slight overshoot, all skipped when `settings.reduceMotion`.
6. **Accent** (user setting) tints the lit nav key, focus, primary keycap, selected segment, gauge. Done = `NocturneStatus.done` green, priorities fixed.
7. Neutral by design: no domain-specific imagery or copy. Keep the app's existing words for labels.
8. Contrast: all text/background pairs ≥ 4.5:1 in both finishes (`neutral500` is the dimmest text token).

## Primitives (`lib/widgets/panel/panel.dart`)
| Widget | Use |
|---|---|
| `panelDecoration` | the one depth recipe |
| `PanelCard(title, trailing, depth)` | grouped content with engraved header |
| `StampLabel` | engraved caption |
| `IndicatorLamp(on, color)` | round lamp, unlit = same hue at low value |
| `GaugeBar(value)` | segmented LED progress, replaces `LinearProgressIndicator` |
| `NocturneButton` (primary/secondary/ghost) | keycap, travels 2px |
| `NocturneTag` | stamped plate (priority / due / generic) |
| `NocturneSegmented` | recessed housing, selected = lit keycap |
| `WobbleCheckbox` | toggle switch + lamp. **Still a real `Checkbox` underneath** (transparent, scaled) so taps, focus, semantics and tests are unchanged. |

Material `Card`, `Dialog`, `TextField`, `FilledButton`, `Switch`, `PopupMenu` are
themed in `buildNocturneTheme` (raised plate / recessed well). Prefer them for
simple cases; use `PanelCard` where the full bevel matters.

## Multi-user cue vocabulary (restyle of existing data only)
- **Role plate**: engraved plate `MEMBER` / `MANAGER` (manager has a double rule — not colour-dependent). Where text "Manager"/"Member" shows today.
- **Department plate**: neutral stamped name; Operator and IT departments get a distinct plate shape plus a lamp (company-wide access). Where department names show today.
- **Assignee chip**: initials badge in a recessed well; editable (manager) = keycap dropdown, read-only (member) = flat inset readout; unassigned = empty dark badge.
- Owner / department-on-project / comment-author cues are **not built** — see `docs/proposals/multiuser-cues.md`.

## Screens must be checked in
dark + light; signed-out (single user) and signed-in as member, manager, IT, Operator; loading / error / empty; narrow (sidebar collapsed) and wide.

## Fonts (self-hosted, SIL OFL, licences alongside)
Barlow Regular 400 + Medium 500, Barlow Condensed SemiBold 600. Inter is
removed once nothing references it.
