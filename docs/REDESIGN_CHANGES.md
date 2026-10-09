# Redesign changes and how to revert them

Branch `redesign/enterprise`, based on `main` at `7da7860` (the version before
the redesign). Everything below is relative to that commit, so
`git checkout 7da7860 -- <file>` restores any file to its previous state.
Reverting a single screen also undoes its restyle. The old token and widget
names were kept, so old screen files generally still compile against the new
theme; run `flutter analyze` after any partial revert.

## Behavioural changes (not just styling)

| # | Change | Where | To revert |
|---|---|---|---|
| 1 | **Operator department can't be deleted.** The delete button is hidden for everyone, `_deleteDepartment` returns early for it, and a database trigger blocks the delete on every path. | `admin_screen.dart` (commit `2861219`); migration `20261009120000_protect_operator_department.sql` (live project and `combined_setup.sql`) | UI: `git revert 2861219`. Database: `drop trigger protect_operator_department on public.departments; drop function public.prevent_operator_department_delete();` |
| 2 | **Projects grid no longer pages horizontally.** It used to cap at two rows, scroll sideways, and remap the mouse wheel. It is now a wrapping grid that scrolls with the page. Featured card height 280 → 256. | `projects_screen.dart`, `project_card.dart` (`beeb460`) | `git checkout 7da7860 -- lib/screens/projects_screen.dart` (the old file may need the card API from `project_card.dart` too) |
| 3 | **Archived: "Unarchive" is an icon-only button below 720px** (tooltip "Unarchive"). The callback is unchanged. The page is now scrollable. | `archived_screen.dart` | `git checkout 7da7860 -- lib/screens/archived_screen.dart` |
| 4 | **Sidebar below 720px width is a forced 56px rail.** Its expand button and the rail's search key open a drawer instead of changing the saved `sidebarExpanded` setting. At 720px and up, behaviour is as before. | `app_shell.dart`, `app_sidebar.dart` (`b62ea20`) | Remove the `compact` branch in `app_shell.dart` `build`; the `forcedExpanded`/`onToggle` params on `AppSidebar` can stay unused |
| 5 | **Mini-calendar moves into the scrolling nav list on short windows (< 720px high)** instead of being pinned. | `app_sidebar.dart` | Set `calendarInScroll = false` |
| 6 | **Sidebar sign-out row is now a user card** (name, role plate, department plate). Tapping it still confirms and signs out. Collapsed rail still shows the logout icon. | `app_sidebar.dart` | `git checkout 7da7860 -- lib/widgets/sidebar/app_sidebar.dart` (also drops the theme toggle) |
| 7 | **Project detail:** at overlay width ≥ 1200px, tasks and activity/comments are two panes. Below that they stack. The activity/comments panel used to disappear below 640px and is now always reachable. At < 720px the edit/archive/delete/"New task" buttons wrap to their own row. | `project_detail_overlay.dart` | `git checkout 7da7860 -- lib/screens/project_detail_overlay.dart` |
| 8 | **Task rows:** the subtask count moved from the subtitle into the right-hand meta cluster (same "n/m subtasks" text); the assignee avatar now also appears in the row (reads the existing directory providers); each row is an extra Tab stop (see keyboard check-off below). | `task_tile.dart`, `smart_view_task_row.dart` (`beeb460`, `098dbe7`) | `git checkout 7da7860 -- lib/widgets/task_tile.dart lib/widgets/smart_view_task_row.dart` |
| 9 | **Calendar:** below ~590px grid width, day cells are compact (dots and "+N"), and tapping anywhere on a compact cell does what tapping the day number does. | `calendar_screen.dart` (`c9baeb1`) | `git checkout 7da7860 -- lib/screens/calendar_screen.dart` |
| 10 | **Dashboard:** panes reflow by width; with a filter set, all stats follow the filter. Text case: "Recent Activity" → "Recent activity", status "OVERDUE" → "Overdue". | `dashboard_screen.dart` | `git checkout 7da7860 -- lib/screens/dashboard_screen.dart` |
| 11 | **Settings:** row labels beside the backup/restore/test-data/wipe buttons were renamed (Back up your data, Restore from a backup, Test data, Erase everything); Keyboard shortcuts now comes before Backup; the wipe button is a primary button in the danger colour in a "Danger zone" card. All buttons and callbacks are the same. | `settings_screen.dart` | `git checkout 7da7860 -- lib/screens/settings_screen.dart` (also drops the Compact rows switch) |
| 12 | **Admin:** the department row shows the name through its plate (no duplicate text); people list is a table ≥ 600px, stacked rows below. Delete gating otherwise unchanged. | `admin_screen.dart` | as item 1 for the Operator guard; otherwise `git checkout 7da7860 -- lib/screens/admin_screen.dart` |
| 13 | **Templates:** the card "⋮" menu is always visible below 720px (no hover on touch). Editor is two columns ≥ 900px. | `templates_screen.dart`, `task_template_editor_screen.dart` | `git checkout 7da7860 -- <those files>` |
| 14 | **Accent colours.** The 8 swatches are retuned (indigo default; the green and red swatches are gone). The accent is also auto-lightened on dark and deepened on light, so the shown colour can differ from the picked one in lightness. Project colours use the same palette, so existing projects change hue. | `nocturne_theme.dart` (`nocturneAccentPalette`, `tuneAccent`) | Restore the old palette values from `7da7860`; remove the `tuneAccent` call in `buildNocturneTheme` |
| 15 | **Dialog backdrop** is lighter (3px blur, 160ms) than before (8px, 220ms). | `blurred_dialog.dart` | `git checkout 7da7860 -- lib/widgets/blurred_dialog.dart` |
| 16 | **Check-off sound** is now `checkoff_soft.wav` at volume 0.7. The old `checkoff_click.wav` and `checkoff_chime.wav` are still in `assets/sounds/`. | `lib/data/sound_service.dart` | Point `_checkoffAsset`/`_checkoffVolume` at `sounds/checkoff_click.wav` / 0.5 (or the chime at 0.35) |
| 17 | **Fonts:** Barlow and Barlow Condensed are replaced by IBM Plex Sans (400/500/600). | `pubspec.yaml`, `assets/fonts/` | Restore the old font files and pubspec block from `7da7860` and set `_fontFamily`/`kPanelFont` in `nocturne_theme.dart` |

## Added features (all approved)

| Feature | Files | To remove |
|---|---|---|
| Quick light/dark toggle in the sidebar footer (uses the existing `setThemeMode`) | `app_sidebar.dart` (`_ThemeToggle`) | Delete the widget and its two uses |
| "Assigned to me" and department filter chips (Today, Upcoming, Dashboard); client-side only, hidden when signed out | `lib/widgets/task_filter_bar.dart`, the three screens (`3168f87`) | `git revert 3168f87` |
| Ctrl/Cmd+K command palette | `lib/widgets/command_palette.dart`, binding in `app_shell.dart` (`aa58e7d`) | `git revert aa58e7d` |
| Keyboard check-off (↑/↓ move, Space toggles; only when the row itself has focus) | `TaskRowFocus` in `task_tile.dart` (`098dbe7`) | Remove the `TaskRowFocus` wrappers |
| "Compact rows" setting (`compactRows`, default off; old backups import fine) | `settings_provider.dart`, `settings_screen.dart`, task rows (`098dbe7`) | Remove the field and the switch |
| Owner line and "You" assignee label in task detail (from the existing `profile_directory()`) | `task_tile.dart` (`098dbe7`) | Remove the `Owner` row and the "You" case |

## Not changed
Providers, models, queries, RPCs, RLS, auth flow and all existing callbacks.
The only database change is the Operator trigger (item 1).
