-- pgTAP tests for the 15 highest-stakes permission scenarios from
-- docs/PERMISSIONS.md: self-escalation, cross-department leaks, and
-- completed_by/comment-author spoofing. The other ~45 scenarios in that
-- doc's table are manually verified only (see docs/PERMISSIONS.md) and are
-- noted as follow-up work in the PR, not covered here.
--
-- Run with: supabase test db (see supabase/tests/README.md).
begin;
-- 18 assertions cover the 15 scenarios (three have two sub-checks: 10, 11, 13).
select plan(18);

-- ---------------------------------------------------------------- fixtures
-- All fixture rows are inserted as postgres (bypasses RLS); only the
-- assertions below run impersonated as particular users.
-- combined_setup.sql already seeds the one-and-only Operator department
-- plus its Dev account; reuse those (a second Operator department is
-- impossible — unique index) instead of inserting our own.
insert into public.departments (id, name, is_operator, is_it) values
  ('00000000-0000-0000-0000-000000000ee0', 'IT', false, true),
  ('00000000-0000-0000-0000-000000000aa0', 'Dept A', false, false),
  ('00000000-0000-0000-0000-000000000bb0', 'Dept B', false, false);

insert into public.department_roles (id, department_id, name, create_projects, edit_projects, manage_tasks, view_team) values
  ('00000000-0000-0000-0000-000000000a51', '00000000-0000-0000-0000-000000000aa0', 'Senior', true, true, true, true),
  ('00000000-0000-0000-0000-000000000b51', '00000000-0000-0000-0000-000000000bb0', 'B Role', false, false, false, false);

-- The P1 #5/#6 signup backstop (handle_new_user trigger) requires this
-- marker on every auth.users row, same as admin_create_profile stamps it.
-- The trigger also creates the matching public.profiles row itself, so we
-- only seed username/display_name here and set role/department/custom
-- role afterward under the admin-RPC bypass flag.
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000001101', 'it-manager@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"it-manager","display_name":"IT Manager"}'::jsonb),
  ('00000000-0000-0000-0000-000000001102', 'it-member@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"it-member","display_name":"IT Member"}'::jsonb),
  ('00000000-0000-0000-0000-00000000aa01', 'a-manager@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"a-manager","display_name":"A Manager"}'::jsonb),
  ('00000000-0000-0000-0000-00000000aa02', 'a-member@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"a-member","display_name":"A Member"}'::jsonb),
  ('00000000-0000-0000-0000-00000000aa03', 'a-senior@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"a-senior","display_name":"A Senior"}'::jsonb),
  ('00000000-0000-0000-0000-00000000bb01', 'b-manager@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"b-manager","display_name":"B Manager"}'::jsonb),
  ('00000000-0000-0000-0000-00000000bb02', 'b-member@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"b-member","display_name":"B Member"}'::jsonb);

select set_config('procheck.rpc', 'on', true);
update public.profiles set role = 'manager', department_id = '00000000-0000-0000-0000-000000000ee0' where id = '00000000-0000-0000-0000-000000001101';
update public.profiles set role = 'member', department_id = '00000000-0000-0000-0000-000000000ee0' where id = '00000000-0000-0000-0000-000000001102';
update public.profiles set role = 'manager', department_id = '00000000-0000-0000-0000-000000000aa0' where id = '00000000-0000-0000-0000-00000000aa01';
update public.profiles set role = 'member', department_id = '00000000-0000-0000-0000-000000000aa0' where id = '00000000-0000-0000-0000-00000000aa02';
-- a separate statement: check_profile_custom_role() nulls custom_role_id
-- out whenever department_id changes in the same UPDATE.
update public.profiles set role = 'member', department_id = '00000000-0000-0000-0000-000000000aa0' where id = '00000000-0000-0000-0000-00000000aa03';
update public.profiles set custom_role_id = '00000000-0000-0000-0000-000000000a51' where id = '00000000-0000-0000-0000-00000000aa03';
update public.profiles set role = 'manager', department_id = '00000000-0000-0000-0000-000000000bb0' where id = '00000000-0000-0000-0000-00000000bb01';
update public.profiles set role = 'member', department_id = '00000000-0000-0000-0000-000000000bb0' where id = '00000000-0000-0000-0000-00000000bb02';
select set_config('procheck.rpc', 'off', true);

insert into public.projects (id, name, department_id, owner_id) values
  ('00000000-0000-0000-0000-000000000a0a', 'Project A', '00000000-0000-0000-0000-000000000aa0', '00000000-0000-0000-0000-00000000aa01');

insert into public.tasks (id, title, project_id, department_id, owner_id, assignee_id) values
  ('00000000-0000-0000-0000-000000000a5a', 'Task A', '00000000-0000-0000-0000-000000000a0a', '00000000-0000-0000-0000-000000000aa0', '00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-00000000aa02');

insert into public.tasks (id, title, project_id, department_id, owner_id, assignee_id) values
  ('00000000-0000-0000-0000-000000000a5c', 'Personal task', null, '00000000-0000-0000-0000-000000000aa0', '00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-00000000aa02');

-- Assigned to the manager, not the plain member — a-senior has
-- manage_tasks so is a legitimate checker; a-member (plain, no custom
-- role) is not, and is test 6's actor.
insert into public.tasks (id, title, project_id, department_id, owner_id, assignee_id) values
  ('00000000-0000-0000-0000-000000000a5d', 'Task A2', '00000000-0000-0000-0000-000000000a0a', '00000000-0000-0000-0000-000000000aa0', '00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-00000000aa01');

-- helper: impersonate a user for the statements that follow in this transaction
create or replace function pg_temp.login_as(p_user_id uuid) returns void as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
end;
$$ language plpgsql;

-- helper: the seeded Dev account's id, resolved regardless of the caller's
-- RLS visibility (security definer, owned by the superuser running this file).
create or replace function pg_temp.dev_id() returns uuid as $$
  select id from public.profiles where lower(username) = 'dev';
$$ language sql security definer;

-- ------------------------------------------------------------------ tests

-- 1. A member with no custom role cannot create a project (admin gate).
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa02');
select throws_ok(
  $$ insert into public.projects (name, department_id) values ('Rogue', '00000000-0000-0000-0000-000000000aa0') $$,
  NULL, NULL,
  '1: member with no role cannot create a project'
);

-- 2. A member of Dept B cannot see Dept A's projects (cross-department leak).
select pg_temp.login_as('00000000-0000-0000-0000-00000000bb02');
select is(
  (select count(*)::int from public.projects where id = '00000000-0000-0000-0000-000000000a0a'),
  0,
  '2: dept B member cannot see dept A project'
);

-- 3. A member of Dept B cannot comment on a Dept A project.
select pg_temp.login_as('00000000-0000-0000-0000-00000000bb02');
select throws_ok(
  $$ select public.append_project_comment('00000000-0000-0000-0000-000000000a0a',
       jsonb_build_object('id', gen_random_uuid(), 'author', 'x', 'text', 'hi', 'timestamp', now())) $$,
  NULL, NULL,
  '3: dept B member cannot comment on dept A project'
);

-- 4. append_project_comment forces the author server-side, ignoring any
-- client-supplied author claim (P1 #7 authorship-spoofing fix).
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa03');
select public.append_project_comment(
  '00000000-0000-0000-0000-000000000a0a',
  jsonb_build_object('id', gen_random_uuid(), 'author', 'A Manager', 'text', 'hi', 'timestamp', now())
);
select ok(
  (select comments->-1->>'author' from public.projects where id = '00000000-0000-0000-0000-000000000a0a') = 'A Senior',
  '4: comment author is forced server-side, not the client-supplied value'
);

-- 5. A member of Dept B cannot see Dept A project's tasks (cross-dept leak).
select pg_temp.login_as('00000000-0000-0000-0000-00000000bb02');
select is(
  (select count(*)::int from public.tasks where id = '00000000-0000-0000-0000-000000000a5a'),
  0,
  '5: dept B member cannot see dept A project task'
);

-- 6. A member with no role cannot check off a task not assigned to them.
-- RLS filters the row out of the UPDATE rather than raising, so the
-- observable effect is "0 rows touched, state unchanged".
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa02');
update public.tasks set is_checked = true where id = '00000000-0000-0000-0000-000000000a5d';
select is(
  (select is_checked from public.tasks where id = '00000000-0000-0000-0000-000000000a5d'),
  false,
  '6: member cannot check off a task not assigned to them'
);

-- 7. The assignee checking off their own task gets completed_by forced to
-- themselves, even if the update tries to claim someone else did it.
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa02');
update public.tasks
   set is_checked = true, completed_by = '00000000-0000-0000-0000-00000000aa01'
 where id = '00000000-0000-0000-0000-000000000a5a';
select is(
  (select completed_by from public.tasks where id = '00000000-0000-0000-0000-000000000a5a'),
  '00000000-0000-0000-0000-00000000aa02'::uuid,
  '7: completed_by is forced to the real checker, not a client-supplied value'
);

-- 8. Un-checking the task clears completed_by again.
update public.tasks set is_checked = false where id = '00000000-0000-0000-0000-000000000a5a';
select is(
  (select completed_by from public.tasks where id = '00000000-0000-0000-0000-000000000a5a'),
  null,
  '8: completed_by is cleared server-side on un-check'
);

-- 9. A manager of Dept B cannot see a Dept A personal (no-project) task.
select pg_temp.login_as('00000000-0000-0000-0000-00000000bb01');
select is(
  (select count(*)::int from public.tasks where id = '00000000-0000-0000-0000-000000000a5c'),
  0,
  '9: dept B manager cannot see dept A personal task'
);

-- 10. A member cannot self-escalate: cannot make self a manager, move self
-- into the Operator department, or clear their own custom role via a raw
-- UPDATE (the admin RPCs are not the only gate — the trigger is).
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa02');
select throws_ok(
  $$ update public.profiles set role = 'manager' where id = '00000000-0000-0000-0000-00000000aa02' $$,
  NULL, NULL,
  '10a: member cannot make self a manager'
);
select throws_ok(
  $$ update public.profiles set department_id = (select id from public.departments where is_operator) where id = '00000000-0000-0000-0000-00000000aa02' $$,
  NULL, NULL,
  '10b: member cannot move self into the Operator department'
);

-- 11. An IT member cannot move self into the Operator department or
-- promote self to IT manager via a raw UPDATE (the old hole).
select pg_temp.login_as('00000000-0000-0000-0000-000000001102');
select throws_ok(
  $$ update public.profiles set department_id = (select id from public.departments where is_operator) where id = '00000000-0000-0000-0000-000000001102' $$,
  NULL, NULL,
  '11a: IT member cannot move self into the Operator department'
);
select throws_ok(
  $$ update public.profiles set role = 'manager' where id = '00000000-0000-0000-0000-000000001102' $$,
  NULL, NULL,
  '11b: IT member cannot promote self to IT manager'
);

-- 12. The Dev account is pinned to Operator even when the update runs
-- through the admin-RPC bypass flag (P5 restored guard: the dev-pin check
-- sits before the procheck.rpc bypass, so it still blocks it).
select pg_temp.login_as(pg_temp.dev_id());
select set_config('procheck.rpc', 'on', true);
select throws_ok(
  $$ update public.profiles set department_id = '00000000-0000-0000-0000-000000000aa0'
     where id = (select id from public.profiles where lower(username) = 'dev') $$,
  NULL, NULL,
  '12: the Dev account cannot be reassigned, even via the admin-RPC bypass flag'
);
select set_config('procheck.rpc', 'off', true);

-- 13. A manager of Dept B cannot see Dept A's job-title roles, and cannot
-- clear a Dept A member's custom role.
select pg_temp.login_as('00000000-0000-0000-0000-00000000bb01');
select is(
  (select count(*)::int from public.department_roles where department_id = '00000000-0000-0000-0000-000000000aa0'),
  0,
  '13a: dept B manager cannot see dept A job-title roles'
);
select throws_ok(
  $$ select public.set_member_role('00000000-0000-0000-0000-00000000aa03', null) $$,
  NULL, NULL,
  '13b: dept B manager cannot clear a dept A member''s role'
);

-- 14. A manager cannot give a member a role belonging to another
-- department (set_member_role enforces same-department roles).
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa01');
select throws_ok(
  $$ select public.set_member_role('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-000000000b51') $$,
  NULL, NULL,
  '14: a manager cannot assign a member a role from another department'
);

-- 15. The Operator cannot create a second Operator account.
select pg_temp.login_as(pg_temp.dev_id());
select throws_ok(
  $$ select public.admin_create_profile('operator2', 'password1', 'Operator Two', 'manager',
       (select id from public.departments where is_operator)) $$,
  NULL, NULL,
  '15: a second Operator account cannot be created'
);

select * from finish();
rollback;
