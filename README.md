# ProCheck — Teranov Edition

The team edition of [ProCheck](https://github.com/JellevdBerg/procheck-listing-app): shared projects and a live dashboard your whole team sees, instead of just you.

> The original local-only app (no account, no server, nothing leaving your device) still lives at its own repo, unaffected by this fork.

![Dashboard](docs/screenshots/dashboard.png)

## Why this edition

- **One login, everyone synced.** Sign in with a username and password — changes to tasks and projects show up for your teammates live, no refresh needed.
- **Roles that match how a team actually works.** Members see their own work, managers see and assign across their department, IT sees everything.
- **A team view, not just a personal one.** Open task counts and estimated workload per person, at a glance.
- **Everything ProCheck already did.** The dashboard, the calendar, projects with subtasks and templates, real undo history — all still here.

![Calendar with Taskmaster](docs/screenshots/calendar.png)

![Project detail](docs/screenshots/project-detail.png)

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel).

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # generates Hive model adapters
flutter run                                                # or: flutter run -d chrome / -d windows / -d linux
```

Set up and connect a backend in [`supabase/README.md`](supabase/README.md) — without it, the app runs local-only, same as the original.
