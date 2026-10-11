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
pulls containers from `ghcr.io` — unavailable in the sandbox these tests
were first authored in, so they were initially validated against a
hand-built local stand-in instead (plain PostgreSQL 16 + pgTAP built from
source + a minimal stub of
`auth.users`/`auth.identities`/`auth.uid()`/`auth.role()`), then confirmed
green (18/18 assertions) before being committed.

They have since had their first real run through `supabase test db` in
CI (see below) — green, 18/18, no changes needed to the suite itself.
That run did surface one migration bug outside the suite: `supabase start`
replays every migration in strict timestamp order, and
`20261009160000_department_roles.sql` revoked execute on
`admin_create_department(text)`, an overload `20261008140000_it_department.sql`
had already dropped earlier in that same order — fixed by removing the
dead revoke.

One thing a hand-built stand-in needs that `supabase test db` won't: an
explicit `grant execute on function public.is_admin() to authenticated;`
(and the same for `my_department`, `is_dept_manager`,
`has_dept_permission`, `is_it_manager`, `is_operator`, `current_profile`).
These functions are revoked from `public`/`anon` in `combined_setup.sql`
but never re-granted to `authenticated` — on the real Supabase platform
(and its local CLI stack, which mirrors it) that's fine, because Supabase
grants `authenticated` default schema-level EXECUTE privileges outside of
any migration (confirmed against the live "ProCheck Multi-User" project:
`authenticated` already has execute on these). A plain local Postgres has
no such platform default, so a hand-built stand-in needs those grants
added itself — not as a migration in this repo.

## CI

`.github/workflows/ci.yml` runs this suite (`supabase/setup-cli` +
`supabase start` + `supabase test db`) on every pull request and push to
`main`, alongside `flutter analyze`/`flutter test` in a separate job.
