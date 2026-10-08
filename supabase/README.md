# Supabase backend

SQL migrations for the Teranov (team) edition's backend — a free-tier
Supabase project, EU region (Frankfurt), per the multi-user feasibility
write-up.

## Applying the setup (dashboard SQL editor — simplest)

1. Open your Supabase project → **SQL Editor** → **New query**.
2. Open **[`combined_setup.sql`](https://raw.githubusercontent.com/JellevdBerg/ProCheck---Teranov-Edition/feature/supabase-foundation/supabase/combined_setup.sql)**
   in your browser (or in this repo). Select all its text and copy it.
3. **Paste the copied SQL text itself into the SQL editor** — not the file's
   name or path. The editor needs the actual `create table ...` statements;
   pasting just `combined_setup.sql` or a path like
   `migrations/0001_initial_schema.sql` is exactly what produces
   `ERROR: 42601: syntax error at or near "migrations"` — the editor is
   trying to run that text as SQL.
4. Click **Run**. That's the whole setup — schema and RLS policies both, in
   one go.

If you'd rather run them as two separate steps instead, the same statements
are split across `migrations/0001_initial_schema.sql` (schema) and
`migrations/0002_rls_policies.sql` (RLS) — same instructions: open each
file, copy its contents, paste *that* into the SQL editor, run, then move to
the next one.

### Once the CLI is linked

Once the [Supabase CLI](https://supabase.com/docs/guides/cli) is linked to
the project, `supabase db push` applies the two `migrations/` files
directly — no copy-pasting needed. `combined_setup.sql` is only there for
the dashboard path above; keep it in sync with `migrations/` if either
changes.

## Credentials

- **Project URL** and **anon/publishable key**: safe to pass to the app via
  `--dart-define` (see `lib/data/supabase_config.dart`) and safe to have in
  chat/PR descriptions — they're the client-facing keys, not secrets.
- **Service-role key** and **database password**: never committed here,
  never pasted in chat. They go straight into GitHub Actions secrets /
  Supabase project settings by whoever has dashboard access.

## Review before using real department data

The RLS policies in `0002_rls_policies.sql` (also in `combined_setup.sql`)
are the one part of this schema worth a second pair of eyes before any
pilot starts — a wrong policy fails open silently. They currently encode: a
member sees/edits their own tasks, tasks assigned to them, and tasks shared
with their department; a manager additionally sees/edits everyone's tasks
within their own department(s).
