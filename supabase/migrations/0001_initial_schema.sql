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
