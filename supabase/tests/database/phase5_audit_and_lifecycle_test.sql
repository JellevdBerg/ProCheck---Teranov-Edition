-- pgTAP tests for Phase 5 (admin audit log & visibility) of the
-- 2026-10-11 hardening spec: a non-admin can't read other departments,
-- clients can't write admin_audit or fake its actor, a deactivated user
-- can't be assigned, and the Operator can't deactivate themself.
--
-- Run with: supabase test db (see supabase/tests/README.md).
begin;
select plan(6);

-- ---------------------------------------------------------------- fixtures
insert into public.departments (id, name, is_operator, is_it) values
  ('00000000-0000-0000-0000-000000000aa0', 'Dept A', false, false),
  ('00000000-0000-0000-0000-000000000bb0', 'Dept B', false, false);

insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000aa01', 'a-manager@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"a-manager","display_name":"A Manager"}'::jsonb),
  ('00000000-0000-0000-0000-00000000aa02', 'a-member@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"a-member","display_name":"A Member"}'::jsonb),
  ('00000000-0000-0000-0000-00000000bb01', 'b-manager@procheck.local', '{"procheck_provisioned":true}'::jsonb, '{"username":"b-manager","display_name":"B Manager"}'::jsonb);

select set_config('procheck.rpc', 'on', true);
update public.profiles set role = 'manager', department_id = '00000000-0000-0000-0000-000000000aa0' where id = '00000000-0000-0000-0000-00000000aa01';
update public.profiles set role = 'member', department_id = '00000000-0000-0000-0000-000000000aa0', is_active = false where id = '00000000-0000-0000-0000-00000000aa02';
update public.profiles set role = 'manager', department_id = '00000000-0000-0000-0000-000000000bb0' where id = '00000000-0000-0000-0000-00000000bb01';
select set_config('procheck.rpc', 'off', true);

insert into public.projects (id, name, department_id, owner_id) values
  ('00000000-0000-0000-0000-000000000a0a', 'Project A', '00000000-0000-0000-0000-000000000aa0', '00000000-0000-0000-0000-00000000aa01');

create or replace function pg_temp.login_as(p_user_id uuid) returns void as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
end;
$$ language plpgsql;

create or replace function pg_temp.dev_id() returns uuid as $$
  select id from public.profiles where lower(username) = 'dev';
$$ language sql security definer;

-- ------------------------------------------------------------------ tests

-- 1. A manager of Dept A cannot list Dept B by name (departments
-- visibility narrowed from `using (true)` to own-department-or-admin).
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa01');
select is(
  (select count(*)::int from public.departments where id = '00000000-0000-0000-0000-000000000bb0'),
  0,
  '1: dept A manager cannot see dept B in the departments list'
);

-- 2. ...but can still see their own department.
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa01');
select is(
  (select count(*)::int from public.departments where id = '00000000-0000-0000-0000-000000000aa0'),
  1,
  '2: dept A manager can still see their own department'
);

-- 3. A client (even an admin-tier one, via the Dev/Operator account)
-- cannot insert into admin_audit directly — there is no insert policy at
-- all, so a direct table write is refused regardless of role.
select pg_temp.login_as(pg_temp.dev_id());
select throws_ok(
  $$ insert into public.admin_audit (actor_id, action, target_type)
     values (pg_temp.dev_id(), 'fake_action', 'profile') $$,
  NULL, NULL,
  '3: a client cannot write admin_audit directly, even as the Operator'
);

-- 4. A client cannot call log_admin_audit() as an RPC to fake an actor —
-- execute was revoked from authenticated entirely.
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa01');
select throws_ok(
  $$ select public.log_admin_audit('fake_action', 'profile', '00000000-0000-0000-0000-00000000aa02') $$,
  NULL, NULL,
  '4: a client cannot call log_admin_audit() directly to fake an actor'
);

-- 5. A deactivated person cannot be assigned a task, even by their own
-- department's manager (server-side, not just hidden in the picker).
select pg_temp.login_as('00000000-0000-0000-0000-00000000aa01');
select throws_ok(
  format(
    $$ insert into public.tasks (title, project_id, owner_id, assignee_id)
       values ('Task for inactive', %L, %L, %L) $$,
    '00000000-0000-0000-0000-000000000a0a',
    '00000000-0000-0000-0000-00000000aa01',
    '00000000-0000-0000-0000-00000000aa02'
  ),
  NULL, NULL,
  '5: a deactivated person cannot be assigned a task'
);

-- 6. The Operator cannot act on their own account through the DB-level
-- admin functions (admin_delete_profile) — the same self-targeting guard
-- the admin-users Edge Function''s deactivate/reactivate actions mirror
-- in TypeScript; that half can only be verified against a deployed
-- function, out of reach of this suite.
select pg_temp.login_as(pg_temp.dev_id());
select throws_ok(
  $$ select public.admin_delete_profile(pg_temp.dev_id()) $$,
  NULL, NULL,
  '6: the Operator cannot act on their own account via admin_delete_profile'
);

select * from finish();
rollback;
