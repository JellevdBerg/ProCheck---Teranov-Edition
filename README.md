# ProCheck — Teranov Edition

The team/multi-user fork of [ProCheck](https://github.com/JellevdBerg/procheck-listing-app), built for company-wide use: Supabase-backed accounts, roles, department-scoped visibility, task assignment, and realtime sync across everyone's devices.

> The original local-only app (no account, no server, nothing leaving your device) continues to live unaffected at its own repo. This fork adds a backend on top of the same task/project/calendar UI — see [`supabase/README.md`](supabase/README.md) for how the backend is set up and maintained.

![Dashboard](docs/screenshots/dashboard.png)

## What this edition adds

- **Username/password sign-in**, no email anywhere in the UI (see [`supabase/README.md`](supabase/README.md#usernamepassword-auth-no-email-in-the-ui) for how that maps to Supabase Auth under the hood).
- **Roles**: Member (own + assigned + department-shared tasks), Manager (everyone's tasks within their department, plus assignment), Operator (IT — sets up departments, sees/edits everything).
- **Task assignment and time estimates**, manager-only, surfaced right on each task.
- **A Team screen** showing open task counts and estimated workload per person, for managers.
- **Realtime sync** — task and project changes made by one signed-in user appear for everyone else live, via Supabase's Postgres Changes.
- Everything else — the dashboard, the calendar, projects with subtasks/priorities/templates, undo history — is the same ProCheck you'd get from the local-only app, now backed by a shared database instead of on-device storage alone.

![Calendar with Taskmaster](docs/screenshots/calendar.png)

![Project detail](docs/screenshots/project-detail.png)

## Platforms

One Flutter codebase — Android, iOS, web, and Windows/Linux/macOS desktop all build and run from this repo. CI currently builds and publishes release artifacts for macOS and Windows on version bumps ([Releases](../../releases)); the other platforms build fine locally via `flutter run`/`flutter build` but don't yet have a CI workflow here.

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) and a Supabase project (see [`supabase/README.md`](supabase/README.md) to set one up).

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # generates Hive model adapters

flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxxx
```

Running with no `--dart-define`s at all still boots the app in local-only mode (useful for working on UI that doesn't touch auth/sync). For day-to-day development, put those two flags in a gitignored `--dart-define-from-file` JSON instead of typing them each time.

## Backend

All schema, RLS policies, and setup/migration instructions live in [`supabase/README.md`](supabase/README.md). Service-role keys and database passwords are never committed here or passed to the app — only the project URL and anon/publishable key, which are safe to share.
