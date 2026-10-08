-- Clarification from Thomas (2026-10-08): managers do the planning and
-- task assignment, and that happens at the project level — members cannot
-- file their tasks into a project at all. So:
--   - A member's tasks always have project_id = null (personal/unfiled).
--   - Only a manager can create or move a task into a project.
-- This replaces tasks_insert_own and tasks_update from
-- 0002_rls_policies.sql with versions that add that check; everything else
-- about those two policies (who can act on which rows) is unchanged.

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
