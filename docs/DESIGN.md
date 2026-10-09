# ProCheck enterprise UI — design spec

Visual change only. Providers, models, data calls, callbacks and routes are
not touched. One design, two themes: **light** and **dark**, tuned separately
(not inverted). Follows the system setting by default; Settings → Appearance
(System / Light / Dark, persisted) and a quick toggle in the sidebar footer
override it. Swiss foundation, utilitarian enterprise: clean grid, one sans,
neutral surfaces, dense rows. Colour carries meaning; personality lives in the
check-off moment and the accent.

## Rules (read before touching a screen)
1. **Never hard-code colours.** Use `context.nocturne` (tokens), `context.nocturneAccent` (already tuned for the theme), `context.departmentColor(key)`. Token names are stable; in dark the ramp runs light→dark with the number, in light it is inverted so roles stay the same:
   `bg` canvas · `surface` cards/rows · `raised` sidebar/headers/hover · `edge` 1px border · `borderStrong` inputs · `well` field fill · `text` · `neutral100..500` text ramp (500 = dimmest text, ≥4.5:1) · `neutral600` icons · `neutral700` strong border · `neutral800/900` subtle fills · status text colours `done` `danger` `warn` `low`.
   `hi`/`lo` are legacy and unused — do not use them.
2. **Colour means one thing.** Green = done, plus the Low priority tag (which also carries a glyph and text). Red (`danger`) = overdue / high priority / destructive. Amber (`warn`) = due soon / medium. Accent = selection, focus, primary action. Department hue = which department. Never colour alone: pair with text, glyph or shape.
3. **Flat.** Depth is a fill and a 1px border (`panelDecoration`: raised = card, recessed = field/track, flat = printed-on). No bevels, no gradients, no shadows — except dialogs, menus and popovers (already in the theme). Don't hand-roll box shadows.
4. **Grid and rhythm.** 4px grid (`NocturneSpace.s1..s8` = 4,8,12,16,24,32). Radius 4 chips / 6 controls / 8 cards (`NocturneRadius`). List rows ~40px; page gutter 16 (compact) / 24+ (wider). Sentence case everywhere except `StampLabel` section captions.
5. **Type** — IBM Plex Sans 400/500/600 only (`kPanelFont` is now the same family; don't reach for it, use the theme `textTheme`). Scale: caption 11/16 · meta 12/16 · dense body 13/20 (default) · body 14/20 · title 16/24 · heading 20/28 · page title 28/36. Tabular figures are on by default. Don't set `fontFamily` yourself.
6. **Responsive.** Decide from the width the widget is *given* (`LayoutBuilder`), using `NocturneBreakpoints`: `<720` compact, `<1200` medium, `<1800` standard, `≥1800` wide. No horizontal scrolling, no clipped or overlapping elements, nothing unreachable at any width ≥ 360. Compact: single column, toolbars wrap, secondary actions may move into a "⋯" menu (still reachable). Wide: add columns / panes rather than stretching rows; cap line-length with a max content width where it's prose or a list. Use `Wrap`, `Flexible`/`Expanded`, `ellipsis`; never fixed widths wider than the narrowest supported viewport.
7. **Motion** is short and functional (≤ 200ms, ease-out); skip when `settings.reduceMotion`. The check-off moment (tick draws, box fills green, one ring pulse, progress bar eases, sound) is the only expressive animation.
8. **Contrast**: text/background pairs ≥ 4.5:1 in both themes. Check light *and* dark.
9. Neutral by design: no domain-specific imagery or copy; the app serves every department. Keep the app's existing words for labels.

## Primitives
| Widget | Use |
|---|---|
| `panelDecoration` / `PanelCard(title, trailing, depth)` | surfaces |
| `StampLabel` / `NocturneSectionLabel` | 11px tracked uppercase caption |
| `IndicatorLamp(on, color)` | status dot (solid = on, ring = off) |
| `GaugeBar(value)` | thin progress bar, eases to new values |
| `NocturneButton` (primary/secondary/ghost, `dense`) | buttons, 32px (28 dense) |
| `NocturneTag` (`forPriority`) | chips: priority (colour + glyph), due, generic |
| `NocturneSegmented` | view/option toggles; selected = accent tint |
| `WobbleCheckbox` | the check-off tick. **Still a real `Checkbox` underneath** so taps, focus, semantics and tests are unchanged. |

Material `Card`, `Dialog`, `TextField`, `FilledButton`, `Switch`, `PopupMenu`
are themed in `buildNocturneTheme`. Prefer them for simple cases. A `ListTile`
inside a filled `DecoratedBox` hides its ink and trips a framework assertion:
wrap it in a `Material(color: …, shape: …)` instead.

## Multi-user cue vocabulary (restyle of existing data only)
Same everywhere (sidebar, Team, Admin, task detail, project cards, activity):
- **Role** — `RolePlate`: text chip. Manager filled, Member outlined.
- **Department** — `DepartmentPlate`: hue dot + name. Operator and IT get a glyph (shield / terminal) on a tinted pill instead of the dot (company-wide access).
- **Person (owner / assignee / author)** — `AvatarWell` initials. Manager sees the editable assignee dropdown; member sees a read-only chip; unassigned = dashed empty avatar. "You" for the signed-in user.
- Operator department can never be deleted (UI hides it; DB trigger enforces it).

## Screens must be checked in
light + dark; signed-out (single user) and signed-in as member, manager, IT, Operator; loading / error / empty; widths 360 / 640 / 960 / 1280 / 1920 / 2560.

## Fonts and sound
IBM Plex Sans Regular/Medium/SemiBold, self-hosted, SIL OFL (`assets/fonts/IBMPlexSans-OFL.txt`). Check-off sound: `assets/sounds/checkoff_soft.wav` (a soft ~130ms pluck); `checkoff_click.wav` and `checkoff_chime.wav` remain, and `SoundService` documents how to switch back.

## Added with the redesign (approved)
Quick theme toggle (sidebar footer) · soft check-off sound · "Assigned to me" / department filter chips (Today, Upcoming, Dashboard) · Ctrl/Cmd+K command palette · keyboard check-off (↑/↓ + Space on a focused row) · Compact rows setting · owner line and "You" label in task detail (via the existing `profile_directory()`).
