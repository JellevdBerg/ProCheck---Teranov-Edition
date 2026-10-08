/// Which top-level destination the [AppShell]'s main content area shows.
/// Project detail is deliberately not one of these — it's an overlay on
/// top of whatever screen was showing, not a destination of its own (see
/// `ProjectDetailOverlay`). Search isn't one either — it's an inline
/// type-ahead field in the sidebar, not a page (see `AppSidebar`).
enum AppScreen {
  projects,
  today,
  upcoming,
  calendar,
  day,
  templates,
  archived,
  settings,
  dashboard,
  team,
  admin,
}
