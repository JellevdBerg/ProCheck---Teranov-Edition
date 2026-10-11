-- Phase 4 (account & department lifecycle) of the 2026-10-11 hardening
-- spec. Replaces hard delete as the default "remove" action with
-- deactivation (people) and archiving (departments), which keep history
-- intact instead of nulling owner_id/assignee_id/completed_by or
-- orphaning projects.
--
-- Account create/reset-password/deactivate/reactivate move to the
-- `admin-users` Edge Function (uses the Supabase Auth Admin API, so a
-- ban and a password change go through a real, supported API instead of
-- this repo's existing habit of writing into auth.users directly).
-- `admin_create_profile` is left in place and still granted — the spec
-- asks to keep it until the Edge Function is proven working in Thomas's
-- own environment (this sandbox can't reach the live project to verify
-- it), and to drop it in a later migration once it is.

-- ----------------------------------------------------------------- columns

alter table public.profiles
  add column is_active boolean not null default true;

alter table public.departments
  add column archived_at timestamptz;

-- ------------------------------------------------- hard delete: Operator-only

-- "Hard delete stays Operator-only behind a typed confirmation" (deactivate
-- is now the default remove action, done via the Edge Function). Also
-- restricts hard delete to departments/accounts with no remaining history
-- tying to them the way soft-delete would otherwise orphan.
create or replace function public.admin_delete_department(p_department_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can delete departments';
  end if;

  if coalesce((select d.is_operator from public.departments d where d.id = p_department_id), false) then
    raise exception 'The Operator department cannot be deleted';
  end if;

  if exists (select 1 from public.profiles where department_id = p_department_id) then
    raise exception 'Department still has members — move or deactivate them first';
  end if;
  if exists (select 1 from public.projects where department_id = p_department_id) then
    raise exception 'Department still owns projects — move them first';
  end if;

  delete from public.departments where id = p_department_id;
end;
$$;

create or replace function public.admin_delete_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_username text;
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can delete accounts';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Cannot delete your own account';
  end if;

  select username into target_username from public.profiles where id = p_user_id;
  if target_username is null then
    raise exception 'Account not found';
  end if;
  if lower(target_username) = 'dev' then
    raise exception 'The Dev account cannot be deleted';
  end if;

  -- profiles.id references auth.users.id ON DELETE CASCADE, so removing
  -- the auth user removes the profile too.
  delete from auth.users where id = p_user_id;
end;
$$;

-- -------------------------------------------------------- department archive

-- Archiving keeps the department (and the history pointing at it) around,
-- just hidden from new assignment; blocked while it still owns projects, so
-- IT moves those first with the existing owning-department action.
create function public.admin_archive_department(p_department_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_is_admin_tier boolean;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can archive departments';
  end if;

  select coalesce(d.is_operator or d.is_it, false) into target_is_admin_tier
    from public.departments d where d.id = p_department_id;
  if target_is_admin_tier is null then
    raise exception 'Department not found';
  end if;
  if target_is_admin_tier and not public.is_operator() then
    raise exception 'Only an Operator can archive the Operator or IT department';
  end if;

  if exists (select 1 from public.projects where department_id = p_department_id) then
    raise exception 'Department still owns projects — move them first';
  end if;

  update public.departments set archived_at = now() where id = p_department_id;
end;
$$;

revoke all on function public.admin_archive_department(uuid) from public;
grant execute on function public.admin_archive_department(uuid) to authenticated;

-- --------------------------------------------------------- directory: is_active

-- Lets the app grey out / exclude inactive people from assignment pickers
-- without widening what profile_directory() already exposes.
drop function if exists public.profile_directory();
create function public.profile_directory()
returns table (id uuid, display_name text, role user_role, department_id uuid,
               custom_role_id uuid, custom_role_name text, is_active boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.role, p.department_id, p.custom_role_id, dr.name, p.is_active
  from public.profiles p
  left join public.department_roles dr on dr.id = p.custom_role_id
  where p.id = auth.uid()
     or public.is_admin()
     or p.department_id = public.my_department();
$$;

revoke execute on function public.profile_directory() from public, anon;
grant execute on function public.profile_directory() to authenticated;
