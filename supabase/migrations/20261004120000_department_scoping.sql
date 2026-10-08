-- Clarification from Thomas (2026-10-08): the local "workspace" switcher
-- (a per-device data silo, unrelated to the backend) is replaced entirely
-- by department. Department is now the hard visibility boundary — people
-- in different departments can't see each other's work — except for one
-- special "Operator" department, whose members see across every
-- department. Every task/project now carries a department indicator
-- (auto-filled from its creator's own department, not freely chosen), and
-- a manager's department-wide visibility is now a direct check against
-- that column instead of joining through other people's profiles.
--
-- Department assignment itself (who's in which department, and the
-- Operator department membership) is set via the Supabase dashboard for
-- now — a manager-facing "assign department" screen is UI work for a
-- later pass, not part of this backend change.

-- ----- departments: mark the one department that bypasses the boundary -----

alter table departments add column is_operator boolean not null default false;

-- At most one department can be the Operator department — a unique index
-- on a single boolean column only allows one row to hold any given value
-- among the rows it covers, so this caps "is_operator = true" to one row.
create unique index departments_single_operator_idx
  on departments (is_operator)
  where is_operator;

insert into departments (name, is_operator)
select 'Operator', true
where not exists (select 1 from departments where is_operator);

-- Looks up whether the calling user sits in the Operator department.
-- SECURITY DEFINER for the same reason as current_profile(): reading
-- departments/profiles inside a tasks/projects policy must bypass RLS on
-- those tables itself, or it would recurse.
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

-- ----- tasks/projects: department_id becomes mandatory, auto-filled -----

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

-- ----- Replace tasks/projects policies: department is now the boundary -----

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

-- A task is always filed under its creator's own department (enforced
-- below), and only a manager (or Operator) can file it into a project —
-- carried over from 0003_member_task_restrictions.sql.
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
