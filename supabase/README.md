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
2. Open **[`combined_setup.sql`](https://github.com/JellevdBerg/ProCheck---Teranov-Edition/blob/main/supabase/combined_setup.sql)**
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

A handful of migrations were also applied by hand (or via a one-off MCP
`execute_sql` call) with a timestamp different from the one the file was
later given in `migrations/` — the live project's migration-history table
and this repo can drift apart that way. Before trusting the CLI/GitHub
integration to apply the *next* new migration cleanly, confirm the live
history's versions match `migrations/`'s filenames exactly (`supabase
migration list` or the Supabase dashboard's migration history); if they
don't, reconcile with `supabase migration repair --status applied
<version>` (to relabel a live entry) rather than editing an
already-applied migration file, and never apply a file through
`execute_sql` without also inserting its row into
`supabase_migrations.schema_migrations` — the GitHub integration's own
drift check relies on that table matching `migrations/` 1:1.

## Username/password auth, no email in the UI, no self-signup

ProCheck signs people in by username, not email — but Supabase Auth still
requires an email address internally, so the app maps each username to a
synthetic `<username>@procheck.local` address (see
`lib/providers/auth_provider.dart`'s `emailForUsername`). Nothing is ever
sent to that address.

There's no "create account" screen — accounts are created by an Operator,
from the app's own Admin screen (see
`20261008130000_admin_provisioning.sql`'s `admin_create_profile`), which
inserts a pre-confirmed account directly, the same way the Dev seed below
does. Because of that, the dashboard's **"Confirm email"** toggle
(Authentication → Providers → Email) doesn't actually matter for account
creation going forward — it only mattered back when sign-up went through
Supabase's own public email/password flow, which this edition no longer
uses at all.

Removing the sign-up screen only stops the *app* from calling the public
sign-up API — the publishable key can still call it directly. Turning off
**"Allow new users to sign up"** (Authentication → Providers → Email) in
the dashboard closes that off too, but `20261010090000_signup_db_backstop.sql`
now also enforces this at the database level: `handle_new_user()` rejects
any `auth.users` insert that isn't marked by `admin_create_profile`, so a
direct `supabase.auth.signUp()` call fails even if that dashboard toggle
is accidentally left on. `admin_create_profile` isn't affected either
way — it inserts into `auth.users` directly rather than going through that
API.

### The permanent "Dev" / Operator test account

`20261008101500_username_auth_and_dev_seed.sql` seeds a permanent account
— username `Dev`, in the Operator department as a manager — so you can
always sign in and verify how the app looks and behaves for any role. Its
password is **not written here or in any other committed file** — this
repo was briefly public with that password documented in plain text, so
treat it as already compromised: rotate it (Authentication → Users → find
`Dev` → reset password) before relying on it, and don't re-commit the new
one anywhere, including chat or a PR description.

**This is dev/testing only.** Either remove this account or change its
password before any real company rollout.

That migration inserts directly into `auth.users`/`auth.identities`,
which isn't a documented/supported Supabase API — it matches the current
GoTrue schema, but if a future Supabase upgrade changes that schema, the
insert may error. If it does, create the account the normal way instead
(**Authentication → Add user**, email `dev@procheck.local`, choose your
own password, confirm it), then run just the final `update profiles set
role = 'manager', department_id = ...` statement from that file by hand.

A fresh environment still needs *some* way to get a first Operator
account without baking a known password into a committed migration again.
Proposed for a future pass (not done in this PR, since it'd change how
every existing environment seeds, and the already-applied
`20261008101500_username_auth_and_dev_seed.sql` is left as-is rather than
edited after the fact): stop adding new dev/test accounts to
`migrations/`, which ships to every environment including production, and
instead add a local-only `supabase/seed.sql` (gitignored, or committed
with a placeholder password that each developer edits before running
`supabase db reset`) that only ever runs against a local `supabase start`
stack. Whoever first provisions a *new* live project creates its first
Operator account by hand (**Authentication → Add user**, then the
`update profiles ...` statement above) and rotates that password into
their own password manager — never into a file.

### Dashboard settings to verify on this project

These are dashboard-only actions Claude sessions working on this repo
must not change themselves — verify them, don't flip them:

- **Authentication → Providers → Email → "Allow new users to sign up"**
  is **off**. (`20261010090000_signup_db_backstop.sql` enforces this at
  the database level too, once applied — see below — but the dashboard
  toggle is the first line of defense.)
- **The `Dev` account's password is not `testing`** (or any other value
  that was ever committed to this repo or pasted in chat/a PR). Rotate it
  under Authentication → Users if you're not sure.

## Operator admin provisioning

`20261008130000_admin_provisioning.sql` adds two SQL functions the app
calls via `supabase.rpc(...)` from its Admin screen:

- `admin_create_department(p_name)` — adds a department.
- `admin_create_profile(p_username, p_password, p_display_name, p_role, p_department_id)`
  — creates a new account the same way the Dev seed above does (same
  caveat: relies on the current GoTrue schema shape).

Both are `SECURITY DEFINER` and re-check `is_operator()` themselves, so
they're safe to expose to the `authenticated` role — being signed in
isn't enough to call them, only being in the Operator department is. This
migration also adds a `profiles_select_as_operator` RLS policy: without
it, an Operator could only see profiles in their own department (the same
limit a manager has), not the whole company, which the Admin screen needs
to list everyone.

**Fixed in `20261008201500_admin_create_profile_pgcrypto_schema.sql`:**
`admin_create_profile`'s `crypt(...)`/`gen_salt(...)` calls failed with
"function gen_salt(unknown) does not exist" — the function's
`search_path = public` hides pgcrypto, whose functions live in the
`extensions` schema on this project. Schema-qualified both calls
(`extensions.crypt(...)`, `extensions.gen_salt(...)`) instead of widening
the search path.

**Fixed in `20261010090000_signup_db_backstop.sql`:** `admin_create_profile`'s
duplicate-username check compared a lower-cased candidate against the
stored `username` column as-is (`username = clean_username`), which missed
the seeded `Dev` account's original mixed case — `dev` or `DEV` could be
created alongside it. Now compares `lower(username) = clean_username`.

## Comment authorship, and realtime delete leaks

**Fixed in `20261010091000_comment_author_and_replica_identity.sql`:**

- `append_project_comment` validated the comment's jsonb shape but never
  checked the client-supplied `author` field against the caller — anyone
  signed in could attribute a comment to any name. `author` is now always
  overwritten with `(select display_name from current_profile())` before
  the row is stored, regardless of what the client sent.
- `tasks`/`projects` were added to the `supabase_realtime` publication
  (`20261008091500_realtime.sql`) without `REPLICA IDENTITY FULL`. Without
  it, a `DELETE`'s replication payload carries only the primary key, so
  Realtime can't evaluate row-level visibility for the deleted row and
  broadcasts it to every subscriber regardless of RLS. Both tables now use
  `REPLICA IDENTITY FULL`.

## IT department — Operator's near-equal

`20261008140000_it_department.sql` adds a second admin tier: an IT
department with "nearly identical privileges" to Operator (full
company-wide visibility, same Admin screen) except for one asymmetry —
only Operator can create the IT department or place an account into
Operator or IT itself; IT can create ordinary departments and accounts,
but not more admin-tier ones.

This splits the old `is_operator()` check into two functions:
- `is_admin()` — true for Operator **or** IT. Now what the
  tasks/projects/`profiles_select_as_operator` (renamed
  `profiles_select_as_admin`) RLS policies check, and what
  `admin_create_department`/`admin_create_profile` require just to act
  at all.
- `is_operator()` — unchanged, true for Operator only. Now the extra gate
  on the IT-only actions: `admin_create_department`'s new `p_is_it`
  parameter, and placing an account's `p_department_id` into whichever
  department is Operator or IT. An account created into either is forced
  to the `manager` role regardless of the requested role, same as the Dev
  seed.

Same cap as Operator: a unique index allows at most one IT department.

## Removing departments and accounts

`20261008195500_admin_delete_department_and_profile.sql` adds the
delete-side counterparts the Admin screen calls via `supabase.rpc(...)`:

- `admin_delete_department(p_department_id)` — removes a department.
  Members keep their account, just lose that department (the existing
  `profiles.department_id` foreign key is `ON DELETE SET NULL`).
- `admin_delete_profile(p_user_id)` — deletes the `auth.users` row, which
  cascades to the `profiles` row.

Same gating as creation: both are `SECURITY DEFINER` and require
`is_admin()` (Operator or IT) to call at all, and `is_operator()`
specifically to remove the Operator/IT department itself or an account
inside it. Also blocked: deleting your own account, and deleting the
permanent Dev test account.

## Checking off a task already in a project

**Fixed in `20261008204720_task_checkoff_project_rls.sql`:** `tasks_update`'s
`with check` originally required `project_id is null or role = 'manager' or
is_admin()` on *every* update — meant to stop a member filing/moving a task
into a project (`20261003120000_member_task_restrictions.sql`), but as
written it also blocked a member from checking off a task a manager had
already assigned into a project, since toggling `is_checked` is an update
too. The checkoff silently 403'd and never reached the server, so nobody
else ever saw it happen.

Fix: the `with check` no longer looks at `project_id` at all (the
department check is unchanged), and a new `protect_task_project_assignment`
trigger enforces the actual rule — only a manager or Operator/IT can change
`project_id` — by comparing `old.project_id` to `new.project_id` directly.
Same reasoning as `protect_profile_privileges`: RLS's `with check` can't see
a row's previous value, so a trigger is the only way to restrict just the
field that changed.

## Operator developer panel

A section at the bottom of the Admin screen, visible only to Operator
(not IT) — app version, which Supabase project this build points at and
whether its realtime socket is connected, the signed-in user's own
id/role/department, the newest migration this build shipped with (a
compile-time constant in `lib/data/latest_migration.dart`, kept manually
in sync — there's no client-readable table saying what's actually been
applied, since migrations here are often pasted into the SQL editor
rather than run through the CLI), and recent sync errors. That last one
is new instrumentation, not new behavior: `tasks_provider.dart`/
`projects_provider.dart`'s pull/mirror-write failures have always been
caught and silently ignored by design (so a flaky connection or an RLS
rejection never blocks the UI) — `sync_log_provider.dart` just gives
those catch blocks somewhere to report to, capped at the last 20.

## Protecting role/department from self-escalation

`20261008150000_protect_profile_privileges.sql` adds a `BEFORE UPDATE`
trigger on `profiles`. It closes two things at once:

- **The Dev account is pinned to Operator.** Even an admin-authored
  change (Operator or IT updating someone else's row) can't move or
  demote the `dev` account out of Operator — only dropping the trigger
  (or the username check inside it) first would allow that.
- **No one can grant themselves `role`/`department_id`.** The existing
  `profiles_update_own` RLS policy (from `20261001091500_rls_policies.sql`)
  lets any signed-in user update their own profile row with no column
  restriction — RLS's `with check` can't compare against the row's
  *previous* value, so it couldn't express "don't let this column
  change" on its own. The trigger blocks any `role`/`department_id`
  change on a self-update unless the caller is Operator or IT (which
  `admin_create_profile` already was, on creation).

Nothing in the app currently calls `.update()` on `profiles` directly, so
this closes a real gap with no change to current behavior.

**Fixed in `20261008180000_dev_pin_case_insensitive.sql`:** the trigger's
Dev check originally compared `username = 'dev'`, but the seeded account's
username is actually stored as `Dev` (capital D) — a case-sensitive match
that silently never fired, so the pin above did nothing until this fix.
Caught by checking the live database directly rather than assuming the
migration's own literal casing was correct.

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
and IT departments see/edit everything.
