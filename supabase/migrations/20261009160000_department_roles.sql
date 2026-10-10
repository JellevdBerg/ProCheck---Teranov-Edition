-- Custom roles (job titles with a few permissions), per department, plus the
-- guards that make profile role/department/role-assignment tamper-proof.
-- Additive: existing users have no custom role and keep working as plain
-- members; managers are unchanged.

-- ---------------------------------------------------------------- roles table
create table public.department_roles (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments (id) on delete cascade,
  name text not null,
  -- The only things a custom role can add on top of plain member rights.
  -- Everything else (managing roles, promoting managers, adding/removing
  -- members, deleting projects) stays manager-only and has no flag here.
  create_projects boolean not null default false,
  edit_projects boolean not null default false,
  manage_tasks boolean not null default false,
  view_team boolean not null default false,
  created_at timestamptz not null default now(),
  constraint department_roles_name_ok check (
    length(btrim(name)) between 1 and 40
    and lower(btrim(name)) <> 'manager'  -- "Manager" is the one fixed role
  )
);
create unique index department_roles_dept_name_key
  on public.department_roles (department_id, lower(btrim(name)));

alter table public.profiles
  add column custom_role_id uuid references public.department_roles (id) on delete restrict;  -- blocks deleting a role that is still assigned

alter table public.department_roles enable row level security;
revoke all on public.department_roles from anon;
grant select, insert, update, delete on public.department_roles to authenticated;

-- ------------------------------------------------------------------- helpers
create or replace function public.my_department()
returns uuid language sql stable security definer set search_path = public as $$
  select department_id from public.profiles where id = auth.uid();
$$;

create or replace function public.is_dept_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'manager' from public.profiles where id = auth.uid()), false);
$$;

-- Manager, or a member whose custom role carries permission p. Does NOT cover
-- Operator/IT (callers add `is_admin() or ...`).
create or replace function public.has_dept_permission(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select pr.role = 'manager'
        or coalesce(case p
             when 'create_projects' then dr.create_projects
             when 'edit_projects'   then dr.edit_projects
             when 'manage_tasks'    then dr.manage_tasks
             when 'view_team'       then dr.view_team
           end, false)
    from public.profiles pr
    left join public.department_roles dr
      on dr.id = pr.custom_role_id and dr.department_id = pr.department_id
    where pr.id = auth.uid()
  ), false);
$$;

create or replace function public.is_it_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'manager' and d.is_it
    from public.profiles p join public.departments d on d.id = p.department_id
    where p.id = auth.uid()
  ), false);
$$;

-- --------------------------------------------------------- roles table policies
create policy department_roles_select on public.department_roles
  for select to authenticated
  using (public.is_admin() or department_id = public.my_department());

create policy department_roles_insert on public.department_roles
  for insert to authenticated
  with check (public.is_admin()
    or (public.is_dept_manager() and department_id = public.my_department()));

create policy department_roles_update on public.department_roles
  for update to authenticated
  using (public.is_admin()
    or (public.is_dept_manager() and department_id = public.my_department()))
  with check (public.is_admin()
    or (public.is_dept_manager() and department_id = public.my_department()));

create policy department_roles_delete on public.department_roles
  for delete to authenticated
  using (public.is_admin()
    or (public.is_dept_manager() and department_id = public.my_department()));

-- A role's department can never change (it would "reach across departments").
create or replace function public.protect_department_role()
returns trigger language plpgsql as $$
begin
  if new.department_id is distinct from old.department_id then
    raise exception 'A role cannot be moved to another department';
  end if;
  return new;
end;
$$;
create trigger protect_department_role_trigger
  before update on public.department_roles
  for each row execute function public.protect_department_role();

-- ----------------------------------------------------- profile tamper-proofing
-- role, department, custom role, username and email may only change inside the
-- admin functions below (they set procheck.rpc), or from the SQL editor /
-- service role (auth.uid() is null). Everything else a user may edit on
-- their own row (display_name) still works.
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or current_setting('procheck.rpc', true) = 'on' then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.role is distinct from old.role
     or new.department_id is distinct from old.department_id
     or new.custom_role_id is distinct from old.custom_role_id
     or new.username is distinct from old.username
     or new.email is distinct from old.email
     or new.created_at is distinct from old.created_at then
    raise exception 'Role, department and username can only be changed by an admin';
  end if;
  return new;
end;
$$;

-- Keeps a custom role valid: only on members, only from the profile's own
-- department; moving department or becoming manager clears it.
create or replace function public.check_profile_custom_role()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE'
     and (new.department_id is distinct from old.department_id or new.role = 'manager') then
    new.custom_role_id := null;
  end if;
  if new.custom_role_id is not null and not exists (
       select 1 from public.department_roles r
       where r.id = new.custom_role_id and r.department_id = new.department_id) then
    raise exception 'That role belongs to another department';
  end if;
  return new;
end;
$$;
create trigger check_profile_custom_role_trigger
  before insert or update on public.profiles
  for each row execute function public.check_profile_custom_role();

-- The Operator department has exactly one user.
create or replace function public.enforce_single_operator()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.department_id is not null
     and (tg_op = 'INSERT' or new.department_id is distinct from old.department_id)
     and exists (select 1 from public.departments d where d.id = new.department_id and d.is_operator)
     and exists (select 1 from public.profiles p
                 where p.department_id = new.department_id and p.id <> new.id) then
    raise exception 'The Operator department has exactly one user';
  end if;
  return new;
end;
$$;
create trigger enforce_single_operator_trigger
  before insert or update of department_id on public.profiles
  for each row execute function public.enforce_single_operator();

-- ------------------------------------------------------------ profile reads
-- Managers, and members whose role has "view_team", see their department's
-- profiles (Team dashboard). Operator/IT still see everyone; everyone sees self.
drop policy if exists profiles_select_department_as_manager on public.profiles;
create policy profiles_select_department_team on public.profiles
  for select to authenticated
  using (department_id = public.my_department()
         and public.has_dept_permission('view_team'));

-- Same people as before, now with the job title.
drop function if exists public.profile_directory();
create function public.profile_directory()
returns table (id uuid, display_name text, role user_role, department_id uuid,
               custom_role_id uuid, custom_role_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.role, p.department_id, p.custom_role_id, dr.name
  from public.profiles p
  left join public.department_roles dr on dr.id = p.custom_role_id
  where p.id = auth.uid()
     or public.is_admin()
     or p.department_id = public.my_department();
$$;

-- --------------------------------------------------- function exposure cleanup
-- Helpers and trigger functions need not be callable by signed-out visitors.
revoke execute on function public.prevent_operator_department_delete() from public, anon, authenticated;
alter function public.prevent_operator_department_delete() set search_path = public;
revoke execute on function public.protect_profile_privileges() from public, anon, authenticated;
revoke execute on function public.check_profile_custom_role() from public, anon, authenticated;
revoke execute on function public.enforce_single_operator() from public, anon, authenticated;
revoke execute on function public.protect_department_role() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.set_department_from_owner() from public, anon, authenticated;
-- None of the helpers below (current_profile, is_admin, is_operator,
-- my_department, is_dept_manager, has_dept_permission, is_it_manager) gets
-- an explicit `grant ... to authenticated` here or anywhere else in this
-- file. That's intentional, not an oversight: Supabase grants authenticated
-- default schema-level EXECUTE outside of any migration, so revoking from
-- public/anon alone is enough on the real platform. A hand-rolled local
-- Postgres standing in for Supabase (e.g. for pgTAP tests) needs those
-- grants added itself — see supabase/tests/README.md.
revoke execute on function public.protect_task_project_assignment() from public, anon, authenticated;
revoke execute on function public.admin_create_department(text) from public, anon;
revoke execute on function public.admin_create_department(text, boolean) from public, anon;
revoke execute on function public.admin_create_profile(text, text, text, text, uuid) from public, anon;
revoke execute on function public.admin_delete_department(uuid) from public, anon;
revoke execute on function public.admin_delete_profile(uuid) from public, anon;
revoke execute on function public.current_profile() from public, anon;
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.is_operator() from public, anon;
revoke execute on function public.profile_directory() from public, anon;
grant execute on function public.profile_directory() to authenticated;
revoke execute on function public.my_department() from public, anon;
revoke execute on function public.is_dept_manager() from public, anon;
revoke execute on function public.has_dept_permission(text) from public, anon;
revoke execute on function public.is_it_manager() from public, anon;
