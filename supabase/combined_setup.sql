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
