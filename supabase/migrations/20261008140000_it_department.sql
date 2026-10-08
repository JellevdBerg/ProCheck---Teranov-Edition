-- Thomas asked (2026-10-08) for an IT department with "nearly identical
-- privileges" to Operator — full company-wide visibility and the same
-- Admin screen access — except for one asymmetry: an Operator can create
-- the IT department and put people in it, but IT can't create another
-- IT (or Operator) department, and can't assign anyone into either.
--
-- Modeled as a second department flag alongside is_operator, with two
-- functions instead of one: is_admin() (true for Operator OR IT — the
-- broad "see/manage everything" check, replacing is_operator() in the
-- tasks/projects/profiles policies below) and the existing is_operator()
-- (true for Operator only — now used strictly for the narrower "can
-- create/assign into an admin-tier department" gate).

-- ----- departments: a second admin-tier flag, capped to one department
-- the same way is_operator is -----

alter table departments add column is_it boolean not null default false;

create unique index departments_single_it_idx
  on departments (is_it)
  where is_it;

-- Broad check: Operator OR IT. Used wherever is_operator() previously
-- meant "sees/manages everything" rather than "is specifically Operator".
create function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (
      select d.is_operator or d.is_it
      from public.profiles p
      join public.departments d on d.id = p.department_id
      where p.id = auth.uid()
    ),
    false
  );
$$;

-- ----- tasks/projects: company-wide bypass now covers IT too -----

drop policy "tasks_select" on tasks;
drop policy "tasks_insert_own" on tasks;
drop policy "tasks_update" on tasks;
drop policy "tasks_delete" on tasks;

create policy "tasks_select"
  on tasks for select
  to authenticated
  using (
    owner_id = auth.uid()
    or assignee_id = auth.uid()
    or public.is_admin()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  );

create policy "tasks_insert_own"
  on tasks for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and (
      department_id = (select department_id from public.current_profile())
      or public.is_admin()
    )
    and (
      project_id is null
      or (select role from public.current_profile()) = 'manager'
      or public.is_admin()
    )
  );

create policy "tasks_update"
  on tasks for update
  to authenticated
  using (
    owner_id = auth.uid()
    or assignee_id = auth.uid()
    or public.is_admin()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  )
  with check (
    (
      department_id = (select department_id from public.current_profile())
      or public.is_admin()
    )
    and (
      project_id is null
      or (select role from public.current_profile()) = 'manager'
      or public.is_admin()
    )
  );

create policy "tasks_delete"
  on tasks for delete
  to authenticated
  using (
    owner_id = auth.uid()
    or public.is_admin()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  );

drop policy "projects_select" on projects;
drop policy "projects_insert_own" on projects;
drop policy "projects_update" on projects;
drop policy "projects_delete" on projects;

create policy "projects_select"
  on projects for select
  to authenticated
  using (
    owner_id = auth.uid()
    or public.is_admin()
    or department_id = (select department_id from public.current_profile())
  );

create policy "projects_insert_own"
  on projects for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and (
      department_id = (select department_id from public.current_profile())
      or public.is_admin()
    )
  );

create policy "projects_update"
  on projects for update
  to authenticated
  using (
    owner_id = auth.uid()
    or public.is_admin()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  )
  with check (
    department_id = (select department_id from public.current_profile())
    or public.is_admin()
  );

create policy "projects_delete"
  on projects for delete
  to authenticated
  using (
    owner_id = auth.uid()
    or public.is_admin()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  );

-- ----- profiles: same bypass, covers IT too -----

drop policy "profiles_select_as_operator" on profiles;

create policy "profiles_select_as_admin"
  on profiles for select
  to authenticated
  using (public.is_admin());

-- ----- admin_create_department: Operator-only can mark a department IT;
-- Operator or IT can create an ordinary department -----

drop function if exists public.admin_create_department(text);

create function public.admin_create_department(p_name text, p_is_it boolean default false)
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

  return new_id;
end;
$$;

revoke all on function public.admin_create_department(text, boolean) from public;
grant execute on function public.admin_create_department(text, boolean) to authenticated;

-- ----- admin_create_profile: Operator or IT can create ordinary
-- accounts; only Operator can place one into the Operator/IT department
-- itself, and any account placed there is forced to manager (same as
-- the Dev seed) regardless of the requested role -----

create or replace function public.admin_create_profile(
  p_username text,
  p_password text,
  p_display_name text,
  p_role text default 'member',
  p_department_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_user_id uuid;
  synthetic_email text;
  clean_username text;
  target_is_admin_tier boolean;
  effective_role text;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can create accounts';
  end if;

  target_is_admin_tier := coalesce(
    (select d.is_operator or d.is_it from public.departments d where d.id = p_department_id),
    false
  );
  if target_is_admin_tier and not public.is_operator() then
    raise exception 'Only an Operator can create accounts in the Operator or IT department';
  end if;

  effective_role := case when target_is_admin_tier then 'manager' else p_role end;
  if effective_role not in ('member', 'manager') then
    raise exception 'role must be ''member'' or ''manager''';
  end if;

  clean_username := lower(trim(p_username));
  if length(clean_username) = 0 then
    raise exception 'Username cannot be empty';
  end if;
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if exists (select 1 from public.profiles where username = clean_username) then
    raise exception 'Username "%" is already taken', clean_username;
  end if;

  synthetic_email := clean_username || '@procheck.local';
  new_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    synthetic_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', clean_username, 'display_name', trim(p_display_name)),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(),
    new_user_id,
    new_user_id::text,
    jsonb_build_object('sub', new_user_id::text, 'email', synthetic_email),
    'email',
    now(), now(), now()
  );

  -- on_auth_user_created already created the profiles row (role='member',
  -- no department) by the time this statement runs — fix both up to what
  -- was actually asked for.
  update public.profiles
  set role = effective_role::user_role,
      department_id = p_department_id
  where id = new_user_id;

  return new_user_id;
end;
$$;
