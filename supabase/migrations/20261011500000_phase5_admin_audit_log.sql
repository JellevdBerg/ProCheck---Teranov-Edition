-- Phase 5 (admin audit log & visibility) of the 2026-10-11 hardening spec.
--
-- admin_audit: who (actor_id, from auth.uid() — never client-supplied)
-- did what to what, written only by the security-definer admin functions
-- below (through the log_admin_audit() helper, which only another
-- SECURITY DEFINER function can call) and by the admin-users Edge
-- Function (via its service-role client). Clients get select-only, and
-- only if they're an admin.

create table public.admin_audit (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  before jsonb,
  after jsonb,
  outcome text not null default 'ok'
);

alter table public.admin_audit enable row level security;
revoke all on public.admin_audit from anon, authenticated;
grant select on public.admin_audit to authenticated;

-- No insert/update/delete policy at all, admin or not — the table is
-- written only through log_admin_audit() (definer-only execute) or the
-- Edge Function's service-role client, never through the client's own
-- session.
create policy admin_audit_select on public.admin_audit
  for select to authenticated
  using (public.is_admin());

create function public.log_admin_audit(
  p_action text,
  p_target_type text,
  p_target_id uuid,
  p_before jsonb default null,
  p_after jsonb default null,
  p_outcome text default 'ok'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_audit (actor_id, action, target_type, target_id, before, after, outcome)
  values (auth.uid(), p_action, p_target_type, p_target_id, p_before, p_after, p_outcome);
end;
$$;

-- Nobody gets direct execute — only another SECURITY DEFINER function
-- calling it internally (Postgres checks privilege against the calling
-- function's own role, not the original client), so a client can never
-- invoke this as an RPC and fake an actor_id/action.
revoke all on function public.log_admin_audit(text, text, uuid, jsonb, jsonb, text)
  from public, anon, authenticated;

-- ------------------------------------------------------- wire logging in

create or replace function public.admin_create_department(p_name text, p_is_it boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can create departments';
  end if;
  if p_is_it and not public.is_operator() then
    raise exception 'Only an Operator can create the IT department';
  end if;
  if length(trim(p_name)) = 0 then
    raise exception 'Department name cannot be empty';
  end if;
  if p_is_it and exists (select 1 from public.departments where is_it) then
    raise exception 'An IT department already exists';
  end if;

  insert into public.departments (name, is_it) values (trim(p_name), p_is_it)
  returning id into new_id;

  perform public.log_admin_audit(
    'create_department', 'department', new_id, null,
    jsonb_build_object('name', trim(p_name), 'is_it', p_is_it));

  return new_id;
end;
$$;

create or replace function public.admin_delete_department(p_department_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  dept public.departments;
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can delete departments';
  end if;

  select * into dept from public.departments where id = p_department_id;
  if dept.id is null then raise exception 'Department not found'; end if;
  if dept.is_operator then
    raise exception 'The Operator department cannot be deleted';
  end if;

  if exists (select 1 from public.profiles where department_id = p_department_id) then
    raise exception 'Department still has members — move or deactivate them first';
  end if;
  if exists (select 1 from public.projects where department_id = p_department_id) then
    raise exception 'Department still owns projects — move them first';
  end if;

  delete from public.departments where id = p_department_id;

  perform public.log_admin_audit(
    'delete_department', 'department', p_department_id,
    jsonb_build_object('name', dept.name, 'is_it', dept.is_it), null);
end;
$$;

create or replace function public.admin_archive_department(p_department_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  dept public.departments;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can archive departments';
  end if;

  select * into dept from public.departments where id = p_department_id;
  if dept.id is null then
    raise exception 'Department not found';
  end if;
  if coalesce(dept.is_operator or dept.is_it, false) and not public.is_operator() then
    raise exception 'Only an Operator can archive the Operator or IT department';
  end if;

  if exists (select 1 from public.projects where department_id = p_department_id) then
    raise exception 'Department still owns projects — move them first';
  end if;

  update public.departments set archived_at = now() where id = p_department_id;

  perform public.log_admin_audit(
    'archive_department', 'department', p_department_id,
    jsonb_build_object('archived_at', dept.archived_at),
    jsonb_build_object('archived_at', now()));
end;
$$;

create or replace function public.admin_delete_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.profiles;
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can delete accounts';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Cannot delete your own account';
  end if;

  select * into target from public.profiles where id = p_user_id;
  if target.id is null then
    raise exception 'Account not found';
  end if;
  if lower(target.username) = 'dev' then
    raise exception 'The Dev account cannot be deleted';
  end if;

  delete from auth.users where id = p_user_id;

  perform public.log_admin_audit(
    'delete_account', 'profile', p_user_id,
    jsonb_build_object('username', target.username, 'department_id', target.department_id),
    null);
end;
$$;

-- Legacy create path (still live until the admin-users Edge Function is
-- verified against the live project — see the Phase 4 migration).
create or replace function public.admin_create_profile(
  p_username text, p_password text, p_display_name text,
  p_role text default 'member', p_department_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  dept public.departments;
  new_user_id uuid;
  synthetic_email text;
  clean_username text;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then raise exception 'Not signed in'; end if;

  select * into dept from public.departments where id = p_department_id;
  if dept.id is null then raise exception 'Pick a department'; end if;
  if p_role not in ('member', 'manager') then
    raise exception 'role must be ''member'' or ''manager''';
  end if;
  if dept.is_operator then
    raise exception 'The Operator department has exactly one user';
  end if;

  if public.is_operator() then
    null;
  elsif dept.is_it then
    if not public.is_it_manager() then
      raise exception 'Only the Operator or an IT manager can add IT accounts';
    end if;
    if p_role = 'manager' then
      raise exception 'Only the Operator can assign IT managers';
    end if;
  elsif public.is_admin() then
    null;
  elsif me.role = 'manager' and me.department_id = dept.id then
    if p_role <> 'member' then
      raise exception 'Managers can add members only';
    end if;
  else
    raise exception 'You are not allowed to create accounts in this department';
  end if;

  clean_username := lower(trim(p_username));
  if length(clean_username) = 0 then raise exception 'Username cannot be empty'; end if;
  if length(p_password) < 6 then raise exception 'Password must be at least 6 characters'; end if;
  if exists (select 1 from public.profiles where lower(username) = clean_username) then
    raise exception 'Username "%" is already taken', clean_username;
  end if;

  synthetic_email := clean_username || '@procheck.local';
  new_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated',
    synthetic_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"],"procheck_provisioned":true}'::jsonb,
    jsonb_build_object('username', clean_username, 'display_name', trim(p_display_name)),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), new_user_id, new_user_id::text,
    jsonb_build_object('sub', new_user_id::text, 'email', synthetic_email),
    'email', now(), now(), now()
  );

  perform set_config('procheck.rpc', 'on', true);
  update public.profiles
     set role = p_role::user_role, department_id = dept.id
   where id = new_user_id;

  perform public.log_admin_audit(
    'create_account', 'profile', new_user_id, null,
    jsonb_build_object('username', clean_username, 'role', p_role, 'department_id', dept.id));

  return new_user_id;
end;
$$;

create or replace function public.set_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.profiles;
  tdept public.departments;
begin
  if p_role not in ('member', 'manager') then
    raise exception 'role must be ''member'' or ''manager''';
  end if;
  select * into target from public.profiles where id = p_user_id;
  if target.id is null then raise exception 'Account not found'; end if;
  select * into tdept from public.departments where id = target.department_id;

  if p_user_id = auth.uid() then raise exception 'You cannot change your own role'; end if;
  if lower(target.username) = 'dev' or coalesce(tdept.is_operator, false) then
    raise exception 'That account''s role is fixed';
  end if;

  if coalesce(tdept.is_it, false) then
    if not public.is_operator() then
      raise exception 'Only the Operator can assign or remove IT managers';
    end if;
  elsif not public.is_admin() then
    raise exception 'Only IT or the Operator can assign or remove managers';
  end if;

  perform set_config('procheck.rpc', 'on', true);
  update public.profiles set role = p_role::user_role where id = p_user_id;

  perform public.log_admin_audit(
    'set_user_role', 'profile', p_user_id,
    jsonb_build_object('role', target.role), jsonb_build_object('role', p_role));
end;
$$;

create or replace function public.set_member_role(p_user_id uuid, p_role_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me public.profiles;
  target public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  select * into target from public.profiles where id = p_user_id;
  if target.id is null then raise exception 'Account not found'; end if;
  if target.role <> 'member' then raise exception 'Only members can have a job title'; end if;

  if not (public.is_admin()
          or (me.role = 'manager' and me.department_id = target.department_id)) then
    raise exception 'You are not allowed to change this person''s role';
  end if;
  if p_role_id is not null and not exists (
       select 1 from public.department_roles r
       where r.id = p_role_id and r.department_id = target.department_id) then
    raise exception 'That role belongs to another department';
  end if;

  perform set_config('procheck.rpc', 'on', true);
  update public.profiles set custom_role_id = p_role_id where id = p_user_id;

  perform public.log_admin_audit(
    'set_member_role', 'profile', p_user_id,
    jsonb_build_object('custom_role_id', target.custom_role_id),
    jsonb_build_object('custom_role_id', p_role_id));
end;
$$;

-- A project's owning department can only change via protect_project_changes
-- (is_admin-gated already); log it there rather than adding a new RPC.
create or replace function public.protect_project_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then return new; end if;
  new.owner_id := old.owner_id;
  if new.department_id is distinct from old.department_id then
    if not public.is_admin() then
      raise exception 'Only IT or the Operator can change a project''s owning department';
    end if;
    perform public.log_admin_audit(
      'set_project_department', 'project', new.id,
      jsonb_build_object('department_id', old.department_id),
      jsonb_build_object('department_id', new.department_id));
  end if;
  return new;
end;
$$;

-- Job-title permission changes are plain table writes (RLS-gated, no
-- dedicated RPC) — log them from a trigger instead.
create function public.log_department_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.log_admin_audit(
    case when tg_op = 'INSERT' then 'create_job_title' else 'edit_job_title' end,
    'department_role', new.id,
    case when tg_op = 'UPDATE' then jsonb_build_object(
      'name', old.name, 'create_projects', old.create_projects,
      'edit_projects', old.edit_projects, 'manage_tasks', old.manage_tasks,
      'view_team', old.view_team) end,
    jsonb_build_object(
      'name', new.name, 'department_id', new.department_id,
      'create_projects', new.create_projects, 'edit_projects', new.edit_projects,
      'manage_tasks', new.manage_tasks, 'view_team', new.view_team));
  return new;
end;
$$;

create trigger log_department_role_change_trigger
  after insert or update on public.department_roles
  for each row execute function public.log_department_role_change();

-- ------------------------------------------------------------------- visibility

-- Was `using (true)` — every signed-in user could list every department's
-- name. Every in-app consumer (sidebar, task filter bar, project/team
-- screens) only ever resolves a department the signed-in user is already
-- scoped to (their own, or — for admins — any), so narrowing this to
-- "own department, or admin" changes nothing a non-admin could already do.
drop policy departments_select_authenticated on public.departments;
create policy departments_select_authenticated on public.departments
  for select to authenticated
  using (public.is_admin() or id = public.my_department());

revoke execute on function public.log_department_role_change() from public, anon, authenticated;

-- A deactivated account was only hidden from the picker client-side —
-- enforce it server-side too, the same way the "same department" check
-- already is.
create or replace function public.set_task_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then return new; end if;
  if exists (select 1 from public.tasks where id = new.id) then return new; end if;
  new.owner_id := auth.uid();
  new.department_id := case
    when new.project_id is not null
      then coalesce(public.task_project_department(new.project_id), public.my_department())
    else public.my_department() end;
  if new.department_id is null then
    raise exception 'You need a department to create tasks';
  end if;
  if new.assignee_id is not null and not public.is_admin() then
    if new.assignee_id <> auth.uid() and not public.has_dept_permission('manage_tasks') then
      raise exception 'You cannot assign tasks to other people';
    end if;
    if not exists (select 1 from public.profiles
                   where id = new.assignee_id and department_id = new.department_id
                     and is_active) then
      raise exception 'The assignee must be an active member of the same department';
    end if;
  end if;
  new.completed_by := case when new.is_checked then auth.uid() end;
  return new;
end;
$$;

create or replace function public.protect_task_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then return new; end if;

  if not public.is_admin() then new.owner_id := old.owner_id; end if;

  if new.project_id is distinct from old.project_id then
    if not (public.is_admin() or public.has_dept_permission('manage_tasks')) then
      raise exception 'Only a manager (or a role that can manage tasks) can move a task into or out of a project';
    end if;
    if not public.is_admin() and new.project_id is not null
       and public.task_project_department(new.project_id) is distinct from public.my_department() then
      raise exception 'That project belongs to another department';
    end if;
    new.department_id := coalesce(public.task_project_department(new.project_id), new.department_id);
  elsif not public.is_admin() then
    new.department_id := old.department_id;
  end if;

  if new.assignee_id is distinct from old.assignee_id
     and new.assignee_id is not null and not public.is_admin() then
    if new.assignee_id <> auth.uid() and not public.has_dept_permission('manage_tasks') then
      raise exception 'You cannot assign tasks to other people';
    end if;
    if not exists (select 1 from public.profiles
                   where id = new.assignee_id
                     and department_id = coalesce(public.task_project_department(new.project_id), new.department_id)
                     and is_active) then
      raise exception 'The assignee must be an active member of the same department';
    end if;
  end if;

  -- Who checked it off is set here, never by the client.
  if new.is_checked is distinct from old.is_checked then
    new.completed_by := case when new.is_checked then auth.uid() end;
  else
    new.completed_by := old.completed_by;
  end if;
  return new;
end;
$$;
