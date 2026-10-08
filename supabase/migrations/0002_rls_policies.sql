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
