# Supabase backend

SQL migrations for the Teranov (team) edition's backend — a free-tier
Supabase project, EU region (Frankfurt), per the multi-user feasibility
write-up.

Migration files under `migrations/` are named with a timestamp prefix
(`20261001090000_initial_schema.sql`, etc.) rather than a plain sequence
number — that's the format the Supabase CLI and its GitHub integration
require to recognize and order them. The prefix doesn't need to reflect the
exact moment a migration was actually applied, only its relative order.

## Applying the setup (dashboard SQL editor — simplest)

1. Open your Supabase project → **SQL Editor** → **New query**.
2. Open **[`combined_setup.sql`](https://github.com/JellevdBerg/ProCheck---Teranov-Edition/blob/feature/supabase-foundation/supabase/combined_setup.sql)**
   on GitHub (the repo's private, so use this page, not a raw link) and hit
   **Copy raw file** (or **Raw** then select-all) to copy its contents.
3. **Paste the copied SQL text itself into the SQL editor** — not the file's
   name or path. The editor needs the actual `create table ...` statements;
   pasting just `combined_setup.sql` or a path like
   `migrations/20261001090000_initial_schema.sql` is exactly what produces
   `ERROR: 42601: syntax error at or near "migrations"` — the editor is
   trying to run that text as SQL.
4. Click **Run**. That's the whole setup — schema and RLS policies both, in
   one go.

If you'd rather run them as two separate steps instead, the same statements
are split across `migrations/20261001090000_initial_schema.sql` (schema) and
`migrations/20261001091500_rls_policies.sql` (RLS) — same instructions: open
each file, copy its contents, paste *that* into the SQL editor, run, then
move to the next one.

### Adding a later migration to an already-set-up project

Once you've run `combined_setup.sql` (or the individual files) once, re-running
it will error on `create table`/`create policy` statements that already
exist. From then on, only run the *new* migration file that was added since
— e.g. `migrations/20261008090000_embedded_fields.sql`
— the same copy-the-contents-and-paste approach, just for that one file.
`combined_setup.sql` itself is still kept up to date for anyone setting up a
fresh project from scratch.

### Once the CLI/GitHub integration is linked

Once the [Supabase CLI](https://supabase.com/docs/guides/cli) (or its GitHub
integration) is linked to the project, pushes to `main` apply any new
`migrations/` file directly — no copy-pasting needed. Because migrations
`20261001090000` through `20261004120000` were applied by hand before the
CLI was ever linked, the CLI's own migration-history table doesn't know
about them — see the project memory/chat for the one-time
`supabase migration repair` step that tells it they're already applied, so
it doesn't try to re-run them. `combined_setup.sql` is only there for the
dashboard path above; keep it in sync with `migrations/` if either changes.

## Username/password auth, no email in the UI

ProCheck signs people in by username, not email — but Supabase Auth still
requires an email address internally, so the app maps each username to a
synthetic `<username>@procheck.local` address (see
`lib/providers/auth_provider.dart`'s `emailForUsername`). Nothing is ever
sent to that address, which means:

- **"Confirm email" must be turned off** for the Email provider —
  **Authentication → Providers → Email → uncheck "Confirm email"** in the
  Supabase dashboard. A synthetic address can never receive a confirmation
  mail, so leaving this on locks every new sign-up out after they create
  an account. This is a dashboard-only toggle; no migration can set it.

### The permanent "Dev" / Operator test account

`20261008101500_username_auth_and_dev_seed.sql` seeds a permanent account
— username `Dev`, password `testing`, in the Operator department as a
manager — so you can always sign in and verify how the app looks and
behaves for any role.

**This is dev/testing only.** `testing` is a deliberately weak password on
a live project. Either remove this account or change its password before
any real company rollout.

That migration inserts directly into `auth.users`/`auth.identities`,
which isn't a documented/supported Supabase API — it matches the current
GoTrue schema, but if a future Supabase upgrade changes that schema, the
insert may error. If it does, create the account the normal way instead
(**Authentication → Add user**, email `dev@procheck.local`, password
`testing`, confirm it), then run just the final `update profiles set
role = 'manager', department_id = ...` statement from that file by hand.

## Credentials

- **Project URL** and **anon/publishable key**: safe to pass to the app via
  `--dart-define` (see `lib/data/supabase_config.dart`) and safe to have in
  chat/PR descriptions — they're the client-facing keys, not secrets.
- **Service-role key** and **database password**: never committed here,
  never pasted in chat. They go straight into GitHub Actions secrets /
  Supabase project settings by whoever has dashboard access.

## Review before using real department data

The RLS policies in `20261001091500_rls_policies.sql` (also in
`combined_setup.sql`) are the one part of this schema worth a second pair of
eyes before any pilot starts — a wrong policy fails open silently. They
currently encode: a member sees/edits their own tasks, tasks assigned to
them, and tasks shared with their department; a manager additionally
sees/edits everyone's tasks within their own department(s); the Operator
department sees/edits everything.
