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

`database/phase5_audit_and_lifecycle_test.sql` (added in the Phase 5
hardening PR) covers the four scenarios that PR's spec item asked for:
a non-admin can't read another department's name (visibility narrowed
from `using (true)`), a client can't write `admin_audit` directly or via
`log_admin_audit()` to fake an actor, a deactivated person can't be
assigned a task, and the Operator can't act on their own account through
the DB-level admin functions (the matching Edge Function self-action
guard is TypeScript and needs a deployed-function integration test, out
of reach here).

## Running it

```
supabase test db
```

pulls containers from `ghcr.io` — unavailable in the sandboxes these tests
were authored in, so both suites were first validated against a
hand-built local stand-in instead: plain PostgreSQL 16 + pgTAP
(`apt-get install postgresql-server-dev-16 postgresql-16-pgtap`, directly
available via apt, no build-from-source needed) + a minimal stub of
`auth.users`/`auth.identities`/`auth.uid()`/`auth.role()`, with every
migration file under `supabase/migrations/` applied in order on top.
`permissions_test.sql` was confirmed green (18/18) this way before being
committed; `phase5_audit_and_lifecycle_test.sql` the same (6/6), run
together with it (24/24) to rule out cross-test interference.

`permissions_test.sql` has since had its first real run through
`supabase test db` in CI (see below) — green, 18/18, no changes needed to
the suite itself. That run did surface one migration bug outside the
suite: `supabase start` replays every migration in strict timestamp
order, and `20261009160000_department_roles.sql` revoked execute on
`admin_create_department(text)`, an overload
`20261008140000_it_department.sql` had already dropped earlier in that
same order — fixed by removing the dead revoke.
`phase5_audit_and_lifecycle_test.sql` hasn't had its first real CI run
yet — give it one before trusting it blindly.

Three things a hand-built stand-in needs that `supabase test db` won't,
because they're platform defaults on real Supabase rather than anything a
migration sets up:
- `grant execute on function public.is_admin() to authenticated;` (and
  the same for `my_department`, `is_dept_manager`, `has_dept_permission`,
  `is_it_manager`, `is_operator`, `current_profile`) — confirmed against
  the live "ProCheck Multi-User" project that `authenticated` already
  has execute on these.
- `grant select, insert, update, delete on all tables in schema public to
  authenticated;` plus `grant usage on all sequences ... to authenticated;`
  — Supabase's own project template grants this at creation time, before
  any migration runs; apply it to the stand-in *before* running the
  migrations (a migration that explicitly revokes/narrows a table, like
  `admin_audit`'s, must still run after, to end up as the final state —
  re-apply that specific revoke if you build the stand-in in this order).
- `create publication supabase_realtime;` — needed only so
  `alter publication supabase_realtime add table ...` and `... replica
  identity full`'s migrations don't error; nothing in these tests
  exercises realtime itself.

## CI

`.github/workflows/ci.yml` runs this suite (`supabase/setup-cli` +
`supabase start` + `supabase test db`) on every pull request and push to
`main`, alongside `flutter analyze`/`flutter test` in a separate job.
