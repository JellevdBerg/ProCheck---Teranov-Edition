-- P1 #7: append_project_comment validated the comment's jsonb shape but
-- never checked p_comment->>'author' against the caller — any signed-in
-- user could pass any author string and have it stored as if someone else
-- wrote it. The author is now always derived from the caller's own
-- profile, overriding whatever the client sent.
create or replace function public.append_project_comment(
  p_project_id uuid,
  p_comment jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  real_comment jsonb;
begin
  if jsonb_typeof(p_comment) is distinct from 'object'
      or not (p_comment ?& array['id', 'author', 'text', 'timestamp']) then
    raise exception 'invalid comment';
  end if;

  real_comment := p_comment || jsonb_build_object(
    'author', (select display_name from public.current_profile())
  );

  update projects
     set comments = comments || jsonb_build_array(real_comment)
   where id = p_project_id;

  if not found then
    raise exception 'project not found or not permitted';
  end if;
end;
$$;

-- P1 #8: tasks/projects were added to the supabase_realtime publication
-- (20261008091500_realtime.sql) without REPLICA IDENTITY FULL. Without it,
-- a DELETE's replication payload carries only the primary key, so
-- Supabase's realtime layer can't evaluate row-level visibility for the
-- deleted row and broadcasts the delete to every subscriber regardless of
-- RLS — leaking that a row with that id existed to clients who should
-- never have seen it.
alter table tasks replica identity full;
alter table projects replica identity full;
