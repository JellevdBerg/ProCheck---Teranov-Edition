-- Phase 3 (sync you can trust): backend support for the client's new
-- persistent outbox.
--
-- 1) `updated_at` on tasks/projects, maintained server-side by a trigger
--    (never trusted from the client, same pattern as `completed_by` /
--    `created_at`). This is foundational plumbing for conflict detection —
--    a client can compare the `updated_at` it last saw against the row's
--    current value to tell whether something else changed a row while an
--    edit sat in its outbox. The outbox replay itself (see
--    `syncable_notifier.dart`) does NOT yet gate on it: Thomas's spec cuts
--    off mid-sentence on the intended conditional-update semantics
--    ("Updates are conditi…"), so rather than guess at a concurrency
--    policy, this PR ships the column/trigger and keeps replay as a plain
--    last-write-wins upsert, same as every other mirror write today. Flagged
--    in the PR description for Thomas to confirm before a follow-up wires
--    up the actual conflict check.
--
-- 2) Idempotent `append_project_activity`/`append_project_comment`: an
--    outbox replay can call either RPC again for an entry that already
--    landed (the request succeeded but the client never saw the response,
--    e.g. the connection dropped right after). Both now no-op instead of
--    appending a duplicate when an entry with the same `id` is already
--    present. `append_project_comment` already required `id`; activity
--    entries didn't carry one until this PR's `ActivityEntry.id` — older
--    entries already stored with no `id` are left alone and never match.

alter table tasks add column if not exists updated_at timestamptz;
alter table projects add column if not exists updated_at timestamptz;

update tasks set updated_at = created_at where updated_at is null;
update projects set updated_at = created_at where updated_at is null;

alter table tasks alter column updated_at set not null;
alter table tasks alter column updated_at set default now();
alter table projects alter column updated_at set not null;
alter table projects alter column updated_at set default now();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger tasks_set_updated_at
  before update on tasks
  for each row execute function public.set_updated_at();

create trigger projects_set_updated_at
  before update on projects
  for each row execute function public.set_updated_at();

-- REPLICA IDENTITY FULL (20261010091000_comment_author_and_replica_identity.sql)
-- already covers DELETE events seeing every column, so realtime UPDATE
-- payloads pick up `updated_at` with no further change needed.

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

  if p_entry ? 'id' and exists (
    select 1
      from projects, jsonb_array_elements(activity_log) as e
     where id = p_project_id
       and e ->> 'id' = p_entry ->> 'id'
  ) then
    return;
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

  if exists (
    select 1
      from projects, jsonb_array_elements(comments) as c
     where id = p_project_id
       and c ->> 'id' = p_comment ->> 'id'
  ) then
    return;
  end if;

  update projects
     set comments = comments || jsonb_build_array(p_comment)
   where id = p_project_id;

  if not found then
    raise exception 'project not found or not permitted';
  end if;
end;
$$;
