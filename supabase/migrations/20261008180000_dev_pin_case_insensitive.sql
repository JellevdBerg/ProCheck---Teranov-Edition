-- Follow-up to 20261008150000_protect_profile_privileges.sql: verifying the
-- pin against the live database (2026-10-08) showed the seeded Dev account's
-- username is actually stored as `Dev` (capital D), not `dev` — so the
-- trigger's case-sensitive `username = 'dev'` check never matched, and the
-- pin silently did nothing. Comparing case-insensitively fixes it.

create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(old.username) = 'dev' then
    if new.department_id is distinct from old.department_id
        or new.role is distinct from old.role then
      raise exception 'The Dev account is pinned to Operator and cannot be reassigned';
    end if;
  end if;

  if not public.is_admin() then
    if new.role is distinct from old.role
        or new.department_id is distinct from old.department_id then
      raise exception 'Only an Operator or IT can change role or department';
    end if;
  end if;

  return new;
end;
$$;
