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
