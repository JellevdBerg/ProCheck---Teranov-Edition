-- Security advisor: public.protect_department_role has a mutable search_path
-- (it was defined in 20261009160000_department_roles.sql without one, unlike
-- every other function in this schema). A mutable search_path lets a caller
-- who can control the session's search_path redirect unqualified references
-- inside the function to objects of their own. This function has none today,
-- but pin it to match the rest of the schema's convention rather than leave
-- the one exception.
create or replace function public.protect_department_role()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.department_id is distinct from old.department_id then
    raise exception 'A role cannot be moved to another department';
  end if;
  return new;
end;
$$;
