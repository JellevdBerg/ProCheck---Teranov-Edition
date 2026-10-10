# Permission tests (pgTAP)

`database/permissions_test.sql` is a [pgTAP](https://pgtap.org/) suite covering
the 15 highest-stakes rows of [`docs/PERMISSIONS.md`](../../docs/PERMISSIONS.md)'s
test table: self-escalation (a member or IT member promoting themselves,
moving departments, or editing the pinned Dev account), cross-department
leaks (seeing or touching another department's projects/tasks/personal
tasks/job-title roles), and server-side spoofing (`completed_by`, a
project comment's `author`).

The other ~45 rows in that table are still manual-only — rolled back by
hand in a Supabase SQL editor transaction — and are not automated here.
Follow-up work, not covered in this PR.

## Running it

```
supabase test db
```

This needs the Supabase CLI and its local stack (`supabase start`), which
pulls containers from `ghcr.io` — unavailable in this sandbox, so these
tests were authored and validated against a hand-built local stand-in
instead (plain PostgreSQL 16 + pgTAP built from source + a minimal stub of
`auth.users`/`auth.identities`/`auth.uid()`/`auth.role()`), then confirmed
green (18/18 assertions) before being committed. They have not been run
through the real `supabase test db` path, so give it a first real run
before trusting it blindly in CI.

One thing the stand-in needed that `supabase test db` won't: an explicit
`grant execute on function public.is_admin() to authenticated;` (and the
same for `my_department`, `is_dept_manager`, `has_dept_permission`,
`is_it_manager`, `is_operator`, `current_profile`). These functions are
revoked from `public`/`anon` in `combined_setup.sql` but never re-granted
to `authenticated` — on the real Supabase platform that's fine, because
Supabase grants `authenticated` default schema-level EXECUTE privileges
outside of any migration (confirmed against the live "ProCheck Multi-User"
project: `authenticated` already has execute on these). A plain local
Postgres has no such platform default, so a hand-built stand-in needs
those grants added itself — not as a migration in this repo.

## CI

Not wired into a workflow yet (the repo only has `macos-build.yml` and
`windows-build.yml`). A `supabase/setup-cli` + `supabase start` + `supabase
test db` job would work fine on GitHub's own runners (unlike this
sandbox), but wasn't added in this PR — follow-up work.
