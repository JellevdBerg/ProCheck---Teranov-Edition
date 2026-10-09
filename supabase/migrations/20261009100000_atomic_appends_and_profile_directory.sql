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
