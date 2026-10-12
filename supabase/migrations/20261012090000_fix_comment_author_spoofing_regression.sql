-- `20261011300000_sync_outbox_support.sql` rewrote `append_project_comment`
-- to add idempotency (skip a comment whose `id` is already present) but
-- dropped the server-side author override that
-- `20261010091000_comment_author_and_replica_identity.sql` added for the
-- P1 #7 authorship-spoofing fix, silently reintroducing it: any signed-in
-- user could post a comment with an arbitrary `author` string. Restore the
-- override while keeping the idempotency check.
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

  if exists (
    select 1
      from projects, jsonb_array_elements(comments) as c
     where id = p_project_id
       and c ->> 'id' = p_comment ->> 'id'
  ) then
    return;
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
