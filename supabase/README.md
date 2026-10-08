# Supabase backend

SQL migrations for the Teranov (team) edition's backend — a free-tier
Supabase project, EU region (Frankfurt), per the multi-user feasibility
write-up.

## Applying the migrations

Via the Supabase dashboard's SQL editor (simplest for now): paste and run
`migrations/0001_initial_schema.sql`, then `migrations/0002_rls_policies.sql`,
in that order.

Once the [Supabase CLI](https://supabase.com/docs/guides/cli) is linked to
the project, `supabase db push` applies both from this folder directly.

## Credentials

- **Project URL** and **anon/publishable key**: safe to pass to the app via
  `--dart-define` (see `lib/data/supabase_config.dart`) and safe to have in
  chat/PR descriptions — they're the client-facing keys, not secrets.
- **Service-role key** and **database password**: never committed here,
  never pasted in chat. They go straight into GitHub Actions secrets /
  Supabase project settings by whoever has dashboard access.

## Review before using real department data

The RLS policies in `0002_rls_policies.sql` are the one part of this schema
worth a second pair of eyes before any pilot starts — a wrong policy fails
open silently. They currently encode: a member sees/edits their own tasks,
tasks assigned to them, and tasks shared with their department; a manager
additionally sees/edits everyone's tasks within their own department(s).
