-- Combined Phase 0 setup: the contents of 20261001090000_initial_schema.sql followed
-- by 20261001091500_rls_policies.sql, concatenated so the whole backend can be set up
-- with a single paste into the Supabase SQL editor. Generated for
-- convenience — the two files under migrations/ are still the source of
-- truth and the ones a future `supabase db push` will apply; keep them in
-- sync with this file if either changes.

-- ===== 20261001090000_initial_schema.sql =====

-- Phase 0: initial multi-user schema for the Teranov (team) edition of
-- ProCheck. This defines the shared backend tables; it does NOT touch the
-- existing local-only Hive storage on the client, which keeps working as-is
-- until a later migration pass points the providers at Supabase.
--
-- Model (see the "Multi-User Feasibility" write-up, "Roles, profiles and
-- assignment" section):
--   - departments: a group a profile belongs to.
--   - profiles: one row per authenticated person (id matches auth.users.id).
--   - projects/tasks: gain owner_id (who created it), assignee_id (who it's
--     for — tasks only), and an optional department_id (who it's shared
--     with). Kept intentionally lean for this first pass: enough to prove
--     out assignment and department visibility, not a 1:1 mirror of every
--     field the local Hive models track (subtasks, attachments, activity
--     log, comments) — those migrate over in a later pass once this schema
--     and its RLS policies have been reviewed.

create extension if not exists "pgcrypto";

create type user_role as enum ('member', 'manager');

create table departments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- One row per person, keyed to Supabase Auth's own user id. Created by a
-- trigger on auth.users (see below) so every signed-up user gets a profile
-- automatically, defaulting to 'member' with no department until a manager
-- (or you, via the dashboard) assigns one.
create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text not null,
  department_id uuid references departments (id) on delete set null,
  role user_role not null default 'member',
  created_at timestamptz not null default now()
);

create table projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  color_index integer not null default 0,
  archived boolean not null default false,
  favorite boolean not null default false,
  owner_id uuid references profiles (id) on delete set null,
  department_id uuid references departments (id) on delete set null,
  created_at timestamptz not null default now(),
  last_opened_at timestamptz
);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  notes text,
  is_checked boolean not null default false,
  project_id uuid references projects (id) on delete set null,
  due_date timestamptz,
  due_date_end timestamptz,
  sort_order double precision not null default 0,
  priority_index integer not null default 0,
  -- Who created the task vs. who it's for — kept as two separate fields
  -- (see the write-up) so a manager can create and assign work without the
  -- assignee's edits being mistaken for the manager's own.
  owner_id uuid references profiles (id) on delete set null,
  assignee_id uuid references profiles (id) on delete set null,
  department_id uuid references departments (id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index tasks_owner_id_idx on tasks (owner_id);
create index tasks_assignee_id_idx on tasks (assignee_id);
create index tasks_department_id_idx on tasks (department_id);
create index tasks_project_id_idx on tasks (project_id);
create index projects_owner_id_idx on projects (owner_id);
create index projects_department_id_idx on projects (department_id);
create index profiles_department_id_idx on profiles (department_id);

-- Auto-create a profile row whenever someone signs up via Supabase Auth, so
-- the app never has to handle "authenticated but no profile yet".
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'display_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ===== 20261001091500_rls_policies.sql =====

-- Row Level Security for the Phase 0 schema. Flagged in the write-up as the
-- one thing most worth a second pair of eyes before any real department
-- data goes through it — a wrong policy fails open silently.
--
-- Visibility rule being encoded (see "Roles, profiles and assignment"):
--   - A member can see/edit tasks & projects they own, are assigned to, or
--     that are shared with their own department.
--   - A manager can additionally see/edit every task & project belonging to
--     anyone in their own department(s), whether or not that item is
--     explicitly department-scoped.

alter table departments enable row level security;
alter table profiles enable row level security;
alter table projects enable row level security;
alter table tasks enable row level security;

-- Looks up the calling user's own profile row. SECURITY DEFINER + a fixed
-- search_path so it bypasses RLS internally (reading profiles inside a
-- profiles policy would otherwise recurse) and queries are explicit about
-- which role/department it returns, instead of each policy duplicating this
-- subselect inline.
create function public.current_profile()
returns public.profiles
language sql
security definer
set search_path = public
stable
as $$
  select * from public.profiles where id = auth.uid();
$$;

-- departments: every signed-in user can read the list (needed to show
-- department names in pickers); nobody writes it from the app in this pass.
create policy "departments_select_authenticated"
  on departments for select
  to authenticated
  using (true);

-- profiles: everyone can read/update their own row.
create policy "profiles_select_own"
  on profiles for select
  to authenticated
  using (id = auth.uid());

create policy "profiles_update_own"
  on profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- profiles: a manager can additionally read profiles in their own
-- department (needed to populate an assignment picker).
create policy "profiles_select_department_as_manager"
  on profiles for select
  to authenticated
  using (
    (select role from public.current_profile()) = 'manager'
    and department_id = (select department_id from public.current_profile())
  );

-- projects: select/update covers "own, or shared with my department, or (as
-- a manager) anyone in my department's".
create policy "projects_select"
  on projects for select
  to authenticated
  using (
    owner_id = auth.uid()
    or department_id = (select department_id from public.current_profile())
    or (
      (select role from public.current_profile()) = 'manager'
      and owner_id in (
        select id from public.profiles
        where department_id = (select department_id from public.current_profile())
      )
    )
  );

create policy "projects_insert_own"
  on projects for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy "projects_update"
  on projects for update
  to authenticated
  using (
    owner_id = auth.uid()
    or (
      (select role from public.current_profile()) = 'manager'
      and owner_id in (
        select id from public.profiles
        where department_id = (select department_id from public.current_profile())
      )
    )
  );

create policy "projects_delete"
  on projects for delete
  to authenticated
  using (
    owner_id = auth.uid()
    or (
      (select role from public.current_profile()) = 'manager'
      and owner_id in (
        select id from public.profiles
        where department_id = (select department_id from public.current_profile())
      )
    )
  );

-- tasks: same shape, plus assignee_id (the assignee always sees/can check
-- off their own tasks, even if department_id is unset).
create policy "tasks_select"
  on tasks for select
  to authenticated
  using (
    owner_id = auth.uid()
    or assignee_id = auth.uid()
    or department_id = (select department_id from public.current_profile())
    or (
      (select role from public.current_profile()) = 'manager'
      and (
        owner_id in (
          select id from public.profiles
          where department_id = (select department_id from public.current_profile())
        )
        or assignee_id in (
          select id from public.profiles
          where department_id = (select department_id from public.current_profile())
        )
      )
    )
  );

-- Whoever creates a task is always its owner — assigning it to someone else
-- afterwards is a separate update, not a different insert path.
create policy "tasks_insert_own"
  on tasks for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy "tasks_update"
  on tasks for update
  to authenticated
  using (
    owner_id = auth.uid()
    or assignee_id = auth.uid()
    or (
      (select role from public.current_profile()) = 'manager'
      and (
        owner_id in (
          select id from public.profiles
          where department_id = (select department_id from public.current_profile())
        )
        or assignee_id in (
          select id from public.profiles
          where department_id = (select department_id from public.current_profile())
        )
      )
    )
  );

create policy "tasks_delete"
  on tasks for delete
  to authenticated
  using (
    owner_id = auth.uid()
    or (
      (select role from public.current_profile()) = 'manager'
      and owner_id in (
        select id from public.profiles
        where department_id = (select department_id from public.current_profile())
      )
    )
  );

-- ===== 20261003120000_member_task_restrictions.sql =====

-- Clarification from Thomas (2026-10-08): managers do the planning and
-- task assignment, and that happens at the project level — members cannot
-- file their tasks into a project at all. So:
--   - A member's tasks always have project_id = null (personal/unfiled).
--   - Only a manager can create or move a task into a project.
-- This replaces tasks_insert_own and tasks_update above with versions that
-- add that check; everything else about those two policies (who can act on
-- which rows) is unchanged.

drop policy "tasks_insert_own" on tasks;
drop policy "tasks_update" on tasks;

create policy "tasks_insert_own"
  on tasks for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and (
      project_id is null
      or (select role from public.current_profile()) = 'manager'
    )
  );

create policy "tasks_update"
  on tasks for update
  to authenticated
  using (
    owner_id = auth.uid()
    or assignee_id = auth.uid()
    or (
      (select role from public.current_profile()) = 'manager'
      and (
        owner_id in (
          select id from public.profiles
          where department_id = (select department_id from public.current_profile())
        )
        or assignee_id in (
          select id from public.profiles
          where department_id = (select department_id from public.current_profile())
        )
      )
    )
  )
  with check (
    project_id is null
    or (select role from public.current_profile()) = 'manager'
  );

-- ===== 20261004120000_department_scoping.sql =====

-- Clarification from Thomas (2026-10-08): the local "workspace" switcher
-- (a per-device data silo, unrelated to the backend) is replaced entirely
-- by department. Department is now the hard visibility boundary — people
-- in different departments can't see each other's work — except for one
-- special "Operator" department, whose members see across every
-- department. Every task/project now carries a department indicator
-- (auto-filled from its creator's own department, not freely chosen), and
-- a manager's department-wide visibility is now a direct check against
-- that column instead of joining through other people's profiles.

alter table departments add column is_operator boolean not null default false;

create unique index departments_single_operator_idx
  on departments (is_operator)
  where is_operator;

insert into departments (name, is_operator)
select 'Operator', true
where not exists (select 1 from departments where is_operator);

create function public.is_operator()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (
      select d.is_operator
      from public.profiles p
      join public.departments d on d.id = p.department_id
      where p.id = auth.uid()
    ),
    false
  );
$$;

update tasks t
  set department_id = p.department_id
  from public.profiles p
  where t.department_id is null and p.id = t.owner_id;

update projects pr
  set department_id = p.department_id
  from public.profiles p
  where pr.department_id is null and p.id = pr.owner_id;

alter table tasks alter column department_id set not null;
alter table projects alter column department_id set not null;

create function public.set_department_from_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.department_id is null then
    new.department_id := (select department_id from public.profiles where id = new.owner_id);
  end if;
  return new;
end;
$$;

create trigger set_task_department before insert on tasks
  for each row execute function public.set_department_from_owner();

create trigger set_project_department before insert on projects
  for each row execute function public.set_department_from_owner();

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
    or public.is_operator()
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
      or public.is_operator()
    )
    and (
      project_id is null
      or (select role from public.current_profile()) = 'manager'
      or public.is_operator()
    )
  );

create policy "tasks_update"
  on tasks for update
  to authenticated
  using (
    owner_id = auth.uid()
    or assignee_id = auth.uid()
    or public.is_operator()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  )
  with check (
    (
      department_id = (select department_id from public.current_profile())
      or public.is_operator()
    )
    and (
      project_id is null
      or (select role from public.current_profile()) = 'manager'
      or public.is_operator()
    )
  );

create policy "tasks_delete"
  on tasks for delete
  to authenticated
  using (
    owner_id = auth.uid()
    or public.is_operator()
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
    or public.is_operator()
    or department_id = (select department_id from public.current_profile())
  );

create policy "projects_insert_own"
  on projects for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and (
      department_id = (select department_id from public.current_profile())
      or public.is_operator()
    )
  );

create policy "projects_update"
  on projects for update
  to authenticated
  using (
    owner_id = auth.uid()
    or public.is_operator()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  )
  with check (
    department_id = (select department_id from public.current_profile())
    or public.is_operator()
  );

create policy "projects_delete"
  on projects for delete
  to authenticated
  using (
    owner_id = auth.uid()
    or public.is_operator()
    or (
      (select role from public.current_profile()) = 'manager'
      and department_id = (select department_id from public.current_profile())
    )
  );

-- ===== 20261008090000_embedded_fields.sql =====

alter table tasks add column subtasks jsonb not null default '[]'::jsonb;
alter table tasks add column attachments jsonb not null default '[]'::jsonb;
alter table tasks add column template_id uuid;

alter table projects add column activity_log jsonb not null default '[]'::jsonb;
alter table projects add column comments jsonb not null default '[]'::jsonb;

-- ===== 20261008091500_realtime_and_estimates.sql =====

alter table tasks add column estimated_minutes integer;

alter publication supabase_realtime add table tasks;
alter publication supabase_realtime add table projects;

-- ===== 20261008101500_username_auth_and_dev_seed.sql =====

alter table profiles add column username text;

update profiles set username = split_part(email, '@', 1) where username is null;

alter table profiles alter column username set not null;
alter table profiles add constraint profiles_username_key unique (username);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, username, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.email)
  );
  return new;
end;
$$;

-- DEV/TESTING ONLY — see the standalone migration file for the full note.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
select
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'dev@procheck.local',
  crypt('testing', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"username":"Dev","display_name":"Dev"}'::jsonb,
  now(), now(), '', '', '', ''
where not exists (select 1 from auth.users where email = 'dev@procheck.local');

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(),
  u.id,
  u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email),
  'email',
  now(), now(), now()
from auth.users u
where u.email = 'dev@procheck.local'
  and not exists (
    select 1 from auth.identities i
    where i.provider = 'email' and i.provider_id = u.id::text
  );

update profiles
set role = 'manager',
    department_id = (select id from departments where is_operator)
where id = (select id from auth.users where email = 'dev@procheck.local');

-- ----- Operator admin provisioning (20261008130000_admin_provisioning.sql) -----

create or replace function public.admin_create_department(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can create departments';
  end if;
  if length(trim(p_name)) = 0 then
    raise exception 'Department name cannot be empty';
  end if;

  insert into public.departments (name) values (trim(p_name))
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.admin_create_department(text) from public;
grant execute on function public.admin_create_department(text) to authenticated;

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
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can create accounts';
  end if;
  if p_role not in ('member', 'manager') then
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

  update public.profiles
  set role = p_role::user_role,
      department_id = p_department_id
  where id = new_user_id;

  return new_user_id;
end;
$$;

revoke all on function public.admin_create_profile(text, text, text, text, uuid) from public;
grant execute on function public.admin_create_profile(text, text, text, text, uuid) to authenticated;

create policy "profiles_select_as_operator"
  on profiles for select
  to authenticated
  using (public.is_operator());

-- ----- IT department tier (20261008140000_it_department.sql) -----

alter table departments add column is_it boolean not null default false;

create unique index departments_single_it_idx
  on departments (is_it)
  where is_it;

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

drop policy "profiles_select_as_operator" on profiles;

create policy "profiles_select_as_admin"
  on profiles for select
  to authenticated
  using (public.is_admin());

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

  update public.profiles
  set role = effective_role::user_role,
      department_id = p_department_id
  where id = new_user_id;

  return new_user_id;
end;
$$;

-- ----- Protect profile privileges (20261008150000_protect_profile_privileges.sql) -----

-- Thomas asked (2026-10-08) to make sure the Dev account always stays in
-- the Operator department. Checking how that could ever change surfaced
-- a real gap, not just a Dev-specific one: `profiles_update_own` (from
-- 20261001091500_rls_policies.sql) lets anyone update their own profile
-- row with no column restriction at all — `role` and `department_id`
-- included. RLS's `with check` can't compare against the row's previous
-- value, so the fix is a trigger, not a tighter policy.
--
-- (Confirmed nothing in the app actually relies on self-service profile
-- updates today — nothing in lib/ calls `.update()` on `profiles` at
-- all — so tightening this changes no current behavior.)

create function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The Dev account is a permanent fixture of the Operator department
  -- (see 20261008101500_username_auth_and_dev_seed.sql) for verifying
  -- role behavior — pinned even against an admin-authored change, not
  -- just self-service ones. If it ever genuinely needs to move, drop
  -- this trigger (or this username check) first.
  if old.username = 'dev' then
    if new.department_id is distinct from old.department_id
        or new.role is distinct from old.role then
      raise exception 'The Dev account is pinned to Operator and cannot be reassigned';
    end if;
  end if;

  -- Everyone else: role/department changes are an admin-tier action
  -- (admin_create_profile already enforces this on creation) — a plain
  -- self-update, like `profiles_update_own` allows, may not touch them.
  if not public.is_admin() then
    if new.role is distinct from old.role
        or new.department_id is distinct from old.department_id then
      raise exception 'Only an Operator or IT can change role or department';
    end if;
  end if;

  return new;
end;
$$;

create trigger protect_profile_privileges_trigger
  before update on profiles
  for each row execute function public.protect_profile_privileges();

-- ----- Dev pin case-insensitive fix (20261008180000_dev_pin_case_insensitive.sql) -----

-- Follow-up to 20261008150000_protect_profile_privileges.sql: verifying the
-- pin against the live database (2026-10-08) showed the seeded Dev account's
-- username is actually stored as `Dev` (capital D), not `dev` — so the
-- trigger's case-sensitive `username = 'dev'` check never matched, and the
-- pin silently did nothing. Comparing case-insensitively fixes it.

create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(old.username) = 'dev' then
    if new.department_id is distinct from old.department_id
        or new.role is distinct from old.role then
      raise exception 'The Dev account is pinned to Operator and cannot be reassigned';
    end if;
  end if;

  if not public.is_admin() then
    if new.role is distinct from old.role
        or new.department_id is distinct from old.department_id then
      raise exception 'Only an Operator or IT can change role or department';
    end if;
  end if;

  return new;
end;
$$;
-- Thomas asked (2026-10-08) to be able to remove departments and
-- individuals, and for IT to have the same privilege as Operator —
-- mirrors the existing admin_create_department/admin_create_profile
-- pattern: both are SECURITY DEFINER RPCs gated on is_admin() (Operator
-- or IT), with the same Operator-only carve-out for the Operator/IT
-- department tier that creation already has.

create function public.admin_delete_department(p_department_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_is_admin_tier boolean;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can delete departments';
  end if;

  target_is_admin_tier := coalesce(
    (select d.is_operator or d.is_it from public.departments d where d.id = p_department_id),
    false
  );
  if target_is_admin_tier and not public.is_operator() then
    raise exception 'Only an Operator can delete the Operator or IT department';
  end if;

  -- profiles.department_id is ON DELETE SET NULL, so members of the
  -- deleted department are kept, just unassigned, rather than blocked
  -- or cascaded away.
  delete from public.departments where id = p_department_id;
end;
$$;

revoke all on function public.admin_delete_department(uuid) from public;
grant execute on function public.admin_delete_department(uuid) to authenticated;

create function public.admin_delete_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_username text;
  target_is_admin_tier boolean;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can delete accounts';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Cannot delete your own account';
  end if;

  select p.username, (d.is_operator or d.is_it)
    into target_username, target_is_admin_tier
  from public.profiles p
  left join public.departments d on d.id = p.department_id
  where p.id = p_user_id;

  if target_username is null then
    raise exception 'Account not found';
  end if;
  if lower(target_username) = 'dev' then
    raise exception 'The Dev account cannot be deleted';
  end if;
  if coalesce(target_is_admin_tier, false) and not public.is_operator() then
    raise exception 'Only an Operator can delete an account in the Operator or IT department';
  end if;

  -- profiles.id references auth.users.id ON DELETE CASCADE, so removing
  -- the auth user removes the profile too.
  delete from auth.users where id = p_user_id;
end;
$$;

revoke all on function public.admin_delete_profile(uuid) from public;
grant execute on function public.admin_delete_profile(uuid) to authenticated;

-- First real account-creation attempt (2026-10-08, after the earlier
-- schema-cache 404 was fixed) hit a new error: "function gen_salt(unknown)
-- does not exist". `admin_create_profile` sets `search_path = public`
-- (needed so its own `is_admin()`/unqualified table references resolve
-- safely), but on this project pgcrypto's `crypt`/`gen_salt` live in the
-- `extensions` schema, not `public` — so the narrowed search path hid
-- them. The Dev-seed migration's own `crypt(...)` call never hit this
-- because it runs as a plain top-level statement, not inside a function
-- with its own `search_path`. Schema-qualifying both calls fixes it
-- without widening the function's search path.

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
    extensions.crypt(p_password, extensions.gen_salt('bf')),
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

  update public.profiles
  set role = effective_role::user_role,
      department_id = p_department_id
  where id = new_user_id;

  return new_user_id;
end;
$$;

-- Thomas reported (2026-10-08) that checking off a task didn't show up for
-- a teammate who should see it. Root cause: `tasks_update`'s WITH CHECK
-- requires `project_id is null or role = 'manager' or is_admin()` on
-- EVERY update to a task row — not just updates that change project_id.
-- That was meant to stop a member from filing/moving a task into a
-- project (see 20261003120000_member_task_restrictions.sql), but as
-- written it also blocks a member from checking off a task a manager
-- already assigned into a project, since that's an update too. The
-- checkoff upsert 403s, is caught and logged by the app's best-effort
-- sync (see [[procheck-postgrest-schema-cache-404]]-style silent
-- failures), and never reaches the server — so nobody else ever sees it.
--
-- Fix: relax the WITH CHECK to not gate on project_id at all (the
-- department check still applies), and move the "only a manager/admin
-- can move a task into or out of a project" rule into a trigger that
-- compares old.project_id vs new.project_id directly — RLS's WITH CHECK
-- can't see the row's previous value, same reason
-- 20261008150000_protect_profile_privileges.sql uses a trigger instead
-- of a tighter policy.

alter policy "tasks_update" on tasks
  with check (
    department_id = (select department_id from public.current_profile())
    or public.is_admin()
  );

create function public.protect_task_project_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.project_id is distinct from old.project_id then
    if not public.is_admin()
        and (select role from public.current_profile()) <> 'manager' then
      raise exception 'Only a manager or Operator/IT can move a task into or out of a project';
    end if;
  end if;
  return new;
end;
$$;

create trigger protect_task_project_assignment_trigger
  before update on tasks
  for each row execute function public.protect_task_project_assignment();


-- ===== 20261009100000_atomic_appends_and_profile_directory.sql =====

-- Two additive pieces; nothing existing is altered, so older app builds keep
-- working unchanged.
--
-- 1) Atomic appends for projects.comments / projects.activity_log.
--    Both are whole-column jsonb arrays that the app used to upsert with the
--    rest of the project row, so two people adding entries at the same time
--    (or one person editing the project with a stale local copy) silently
--    overwrote each other. These functions append ONE entry in a single
--    UPDATE (row-locked, so concurrent appends both land).
--
--    They are SECURITY INVOKER on purpose: the caller's own `projects_update`
--    RLS policy still decides who may write (owner, same-department manager,
--    Operator/IT) — no permission is widened. If RLS hides or refuses the
--    row, no row matches and the function raises, so the app's sync log
--    records the failure instead of it vanishing.
--
-- 2) profile_directory(): lets every signed-in user resolve the display name,
--    role and department of the people in THEIR OWN department (everyone for
--    Operator/IT) without being able to read the full `profiles` table
--    (which also holds the synthetic email and the username). Needed so a
--    plain member can see who owns/is assigned/wrote something; RLS on
--    `profiles` itself is untouched.

create or replace function public.append_project_comment(
  p_project_id uuid,
  p_comment jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if jsonb_typeof(p_comment) is distinct from 'object'
      or not (p_comment ?& array['id', 'author', 'text', 'timestamp']) then
    raise exception 'invalid comment';
  end if;

  update projects
     set comments = comments || jsonb_build_array(p_comment)
   where id = p_project_id;

  if not found then
    raise exception 'project not found or not permitted';
  end if;
end;
$$;

-- Same, for the activity feed, keeping only the newest 200 entries (the same
-- cap the app applies locally).
create or replace function public.append_project_activity(
  p_project_id uuid,
  p_entry jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if jsonb_typeof(p_entry) is distinct from 'object'
      or not (p_entry ?& array['kindIndex', 'description', 'timestamp']) then
    raise exception 'invalid activity entry';
  end if;

  update projects
     set activity_log = (
       select coalesce(jsonb_agg(e order by i), '[]'::jsonb)
         from jsonb_array_elements(activity_log || jsonb_build_array(p_entry))
              with ordinality as t(e, i)
        where i > jsonb_array_length(activity_log) + 1 - 200
     )
   where id = p_project_id;

  if not found then
    raise exception 'project not found or not permitted';
  end if;
end;
$$;

create or replace function public.profile_directory()
returns table (
  id uuid,
  display_name text,
  role public.user_role,
  department_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.role, p.department_id
    from profiles p
   where p.id = auth.uid()
      or public.is_admin()
      or p.department_id = (select department_id from public.current_profile());
$$;

revoke all on function public.append_project_comment(uuid, jsonb) from public, anon;
revoke all on function public.append_project_activity(uuid, jsonb) from public, anon;
revoke all on function public.profile_directory() from public, anon;
grant execute on function public.append_project_comment(uuid, jsonb) to authenticated;
grant execute on function public.append_project_activity(uuid, jsonb) to authenticated;
grant execute on function public.profile_directory() to authenticated;


-- ===== 20261009120000_protect_operator_department.sql =====
-- The Operator department must always exist: it is what is_operator() and the
-- Operator-only admin actions hang off. admin_delete_department() let an
-- Operator remove it. A trigger (rather than a check in that one function)
-- also covers direct deletes and any future RPC. Additive; nothing else changes.

create or replace function public.prevent_operator_department_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'The Operator department cannot be deleted';
end;
$$;

drop trigger if exists protect_operator_department on public.departments;
create trigger protect_operator_department
  before delete on public.departments
  for each row
  when (old.is_operator)
  execute function public.prevent_operator_department_delete();


-- ===== 20261009160000_department_roles.sql =====
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


-- ===== 20261009161000_account_rules.sql =====
-- Who may create / delete accounts and change roles, enforced server-side.
-- These functions are the only way to change a profile's role, department or
-- custom role (see protect_profile_privileges).
--
-- Operator: everything, except there is exactly one Operator account.
-- IT manager: add/remove IT members; everything IT can do.
-- IT member: everything IT can do except touch the IT department's people.
-- IT (any): create departments (existing), add managers and members to any
--   department other than Operator/IT, promote/demote managers there.
-- Department manager: add/remove MEMBERS of their own department, hand out
--   that department's custom roles. Cannot make managers.
-- Only the Operator can create, promote or remove IT managers.

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
    '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated',
    synthetic_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
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

  return new_user_id;
end;
$$;

create or replace function public.admin_delete_profile(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  target public.profiles;
  tdept public.departments;
begin
  select * into me from public.profiles where id = auth.uid();
  select * into target from public.profiles where id = p_user_id;
  if target.id is null then raise exception 'Account not found'; end if;
  select * into tdept from public.departments where id = target.department_id;

  if p_user_id = auth.uid() then raise exception 'Cannot delete your own account'; end if;
  if lower(target.username) = 'dev' then raise exception 'The Dev account cannot be deleted'; end if;
  if coalesce(tdept.is_operator, false) then
    raise exception 'The Operator account cannot be deleted';
  end if;

  if public.is_operator() then
    null;
  elsif coalesce(tdept.is_it, false) then
    if not (public.is_it_manager() and target.role = 'member') then
      raise exception 'Only the Operator can remove IT managers; IT managers can remove IT members';
    end if;
  elsif public.is_admin() then
    null;
  elsif me.role = 'manager' and me.department_id = target.department_id and target.role = 'member' then
    null;
  else
    raise exception 'You are not allowed to delete this account';
  end if;

  delete from auth.users where id = p_user_id;
end;
$$;

-- Promote a member to manager, or demote a manager to member.
create or replace function public.set_user_role(p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
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
end;
$$;

-- Give a member a job title (or clear it with null).
create or replace function public.set_member_role(p_user_id uuid, p_role_id uuid)
returns void language plpgsql security definer set search_path = public as $$
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
end;
$$;

revoke execute on function public.set_user_role(uuid, text) from public, anon;
revoke execute on function public.set_member_role(uuid, uuid) from public, anon;
grant execute on function public.set_user_role(uuid, text) to authenticated;
grant execute on function public.set_member_role(uuid, uuid) to authenticated;
revoke execute on function public.admin_create_profile(text, text, text, text, uuid) from public, anon;
revoke execute on function public.admin_delete_profile(uuid) from public, anon;


-- ===== 20261009162000_project_task_rules.sql =====
-- Projects belong to a DEPARTMENT (never a user); who may create/edit them,
-- who sees which tasks, who may assign, and who checked a task off.
--
-- Projects:  Operator/IT see and change everything (incl. the owning
--   department). Everyone else sees their own department's projects. Create =
--   manager or a role with create_projects; edit/archive = manager or
--   edit_projects; delete = manager only.
-- Tasks in a project: every member of the project's department can see them
--   (so a check-off reaches everyone who should see it, live). Members can
--   change only tasks they own or are assigned; managers (and manage_tasks
--   roles) can create/assign/move them.
-- Personal tasks (no project): the creator, their department manager,
--   Operator and IT only.

alter table public.tasks
  add column completed_by uuid references public.profiles (id) on delete set null;

-- The department that currently owns a task's project (used so a project
-- handed to another department takes its tasks' visibility with it).
create or replace function public.task_project_department(p_project_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select department_id from public.projects where id = p_project_id;
$$;
revoke execute on function public.task_project_department(uuid) from public, anon;
grant execute on function public.task_project_department(uuid) to authenticated;

-- ---------------------------------------------------------------- projects
drop policy projects_select on public.projects;
drop policy projects_insert_own on public.projects;
drop policy projects_update on public.projects;
drop policy projects_delete on public.projects;

create policy projects_select on public.projects for select to authenticated
  using (public.is_admin() or department_id = public.my_department());

-- Real "create" permission is enforced in the insert trigger (the check here
-- also lets edit-only roles through, because the app saves with upsert).
create policy projects_insert on public.projects for insert to authenticated
  with check (public.is_admin()
    or (department_id = public.my_department()
        and (public.has_dept_permission('create_projects')
             or public.has_dept_permission('edit_projects'))));

create policy projects_update on public.projects for update to authenticated
  using (public.is_admin()
    or (department_id = public.my_department()
        and public.has_dept_permission('edit_projects')))
  with check (public.is_admin() or department_id = public.my_department());

create policy projects_delete on public.projects for delete to authenticated
  using (public.is_admin()
    or (department_id = public.my_department() and public.is_dept_manager()));

create or replace function public.set_project_ownership()
returns trigger language plpgsql security definer set search_path = public as $$
declare mydept uuid;
begin
  if auth.uid() is null then return new; end if;
  -- An upsert that lands on an existing row is an update: leave it to the
  -- update guard so it can't re-home the project.
  if exists (select 1 from public.projects where id = new.id) then return new; end if;
  mydept := public.my_department();
  if mydept is null then raise exception 'You need a department to create projects'; end if;
  if not (public.is_admin() or public.has_dept_permission('create_projects')) then
    raise exception 'You are not allowed to create projects';
  end if;
  new.owner_id := auth.uid();   -- "created by" only; ownership is the department
  new.department_id := mydept;
  return new;
end;
$$;
drop trigger set_project_department on public.projects;
create trigger set_project_ownership_trigger
  before insert on public.projects
  for each row execute function public.set_project_ownership();

create or replace function public.protect_project_changes()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  new.owner_id := old.owner_id;
  if new.department_id is distinct from old.department_id and not public.is_admin() then
    raise exception 'Only IT or the Operator can change a project''s owning department';
  end if;
  return new;
end;
$$;
create trigger protect_project_changes_trigger
  before update on public.projects
  for each row execute function public.protect_project_changes();

-- Comments / activity: any member of the owning department (or IT/Operator)
-- may add one entry, without needing edit rights on the project row.
create or replace function public.append_project_comment(p_project_id uuid, p_comment jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(p_comment) is distinct from 'object'
      or not (p_comment ?& array['id', 'author', 'text', 'timestamp']) then
    raise exception 'invalid comment';
  end if;
  if not exists (select 1 from public.projects
                 where id = p_project_id
                   and (public.is_admin() or department_id = public.my_department())) then
    raise exception 'project not found or not permitted';
  end if;
  update public.projects
     set comments = comments || jsonb_build_array(p_comment)
   where id = p_project_id;
end;
$$;

create or replace function public.append_project_activity(p_project_id uuid, p_entry jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(p_entry) is distinct from 'object'
      or not (p_entry ?& array['kindIndex', 'description', 'timestamp']) then
    raise exception 'invalid activity entry';
  end if;
  if not exists (select 1 from public.projects
                 where id = p_project_id
                   and (public.is_admin() or department_id = public.my_department())) then
    raise exception 'project not found or not permitted';
  end if;
  update public.projects
     set activity_log = (
       select coalesce(jsonb_agg(e order by i), '[]'::jsonb)
         from jsonb_array_elements(activity_log || jsonb_build_array(p_entry))
              with ordinality as t(e, i)
        where i > jsonb_array_length(activity_log) + 1 - 200
     )
   where id = p_project_id;
end;
$$;
revoke execute on function public.append_project_comment(uuid, jsonb) from public, anon;
revoke execute on function public.append_project_activity(uuid, jsonb) from public, anon;
grant execute on function public.append_project_comment(uuid, jsonb) to authenticated;
grant execute on function public.append_project_activity(uuid, jsonb) to authenticated;

-- ------------------------------------------------------------------- tasks
drop policy tasks_select on public.tasks;
drop policy tasks_insert_own on public.tasks;
drop policy tasks_update on public.tasks;
drop policy tasks_delete on public.tasks;

create policy tasks_select on public.tasks for select to authenticated
  using (
    public.is_admin()
    or owner_id = auth.uid()
    or assignee_id = auth.uid()
    or (project_id is not null
        and public.task_project_department(project_id) = public.my_department())
    or (project_id is null
        and department_id = public.my_department() and public.is_dept_manager())
  );

create policy tasks_insert on public.tasks for insert to authenticated
  with check (
    owner_id = auth.uid()
    and (
      (project_id is null and (department_id = public.my_department() or public.is_admin()))
      or (project_id is not null and (
            public.is_admin()
            or (public.task_project_department(project_id) = public.my_department()
                and public.has_dept_permission('manage_tasks'))))
    )
  );

create policy tasks_update on public.tasks for update to authenticated
  using (
    public.is_admin()
    or owner_id = auth.uid()
    or assignee_id = auth.uid()
    or (project_id is not null
        and public.task_project_department(project_id) = public.my_department()
        and public.has_dept_permission('manage_tasks'))
    or (project_id is null
        and department_id = public.my_department() and public.is_dept_manager())
  )
  with check (
    public.is_admin()
    or department_id = public.my_department()
    or (project_id is not null
        and public.task_project_department(project_id) = public.my_department())
  );

create policy tasks_delete on public.tasks for delete to authenticated
  using (
    owner_id = auth.uid()
    or public.is_admin()
    or (public.is_dept_manager()
        and coalesce(public.task_project_department(project_id), department_id)
            = public.my_department())
  );

create or replace function public.set_task_ownership()
returns trigger language plpgsql security definer set search_path = public as $$
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
                   where id = new.assignee_id and department_id = new.department_id) then
      raise exception 'The assignee must be in the same department';
    end if;
  end if;
  new.completed_by := case when new.is_checked then auth.uid() end;
  return new;
end;
$$;
drop trigger set_task_department on public.tasks;
create trigger set_task_ownership_trigger
  before insert on public.tasks
  for each row execute function public.set_task_ownership();

create or replace function public.protect_task_changes()
returns trigger language plpgsql security definer set search_path = public as $$
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
                     and department_id = coalesce(public.task_project_department(new.project_id), new.department_id)) then
      raise exception 'The assignee must be in the same department';
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
drop trigger protect_task_project_assignment_trigger on public.tasks;
create trigger protect_task_changes_trigger
  before update on public.tasks
  for each row execute function public.protect_task_changes();

drop function public.protect_task_project_assignment();
drop function public.set_department_from_owner();

revoke execute on function public.set_project_ownership() from public, anon, authenticated;
revoke execute on function public.protect_project_changes() from public, anon, authenticated;
revoke execute on function public.set_task_ownership() from public, anon, authenticated;
revoke execute on function public.protect_task_changes() from public, anon, authenticated;


-- ===== 20261009163000_drop_ambiguous_department_overload.sql =====
-- The one-argument overload made `admin_create_department('x')` ambiguous
-- (the two-argument version has a default). The app always passes both.
drop function if exists public.admin_create_department(text);
