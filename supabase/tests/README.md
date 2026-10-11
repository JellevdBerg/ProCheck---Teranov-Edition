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

This needs the Supabase CLI and its local stack (`supabase start`), which
pulls containers from `ghcr.io` — unavailable in this sandbox, so these
tests were authored and validated against a hand-built local stand-in
instead: plain PostgreSQL 16 + pgTAP (`apt-get install postgresql-server-dev-16
postgresql-16-pgtap`, both available directly via apt on this sandbox's
Ubuntu mirror — no build-from-source needed) + a minimal stub of
`auth.users`/`auth.identities`/`auth.uid()`/`auth.role()`, with every
migration file under `supabase/migrations/` applied in order on top.
`permissions_test.sql` was confirmed green (18/18) before being
committed; `phase5_audit_and_lifecycle_test.sql` the same (6/6), run
together with it (24/24) to rule out cross-test interference. Neither has
been run through the real `supabase test db` path, so give both a first
real run before trusting them blindly in CI.

Three things the stand-in needed that `supabase test db` won't, because
they're platform defaults on real Supabase rather than anything a
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

Not wired into a workflow yet (the repo only has `macos-build.yml` and
`windows-build.yml`). A `supabase/setup-cli` + `supabase start` + `supabase
test db` job would work fine on GitHub's own runners (unlike this
sandbox), but wasn't added in this PR — follow-up work.
