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
