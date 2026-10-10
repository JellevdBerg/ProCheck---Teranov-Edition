-- P5: the explicit "Dev account is pinned to Operator" guard
-- (20261008180000_dev_pin_case_insensitive.sql) was silently dropped when
-- protect_profile_privileges() was rewritten in 20261009160000_department_roles.sql
-- for the new role-tier model — the rewrite kept the general
-- "role/department/username/etc can only change via an admin RPC" check but
-- never carried over the Dev-specific case. Not exploitable today (the
-- admin RPCs that can change role/department — set_user_role,
-- admin_delete_profile — already refuse to touch the `dev` account by
-- username, independently), but this was defense-in-depth against any
-- future RPC that touches department_id/role without its own Dev check,
-- and docs (supabase/README.md's "Protecting role/department from
-- self-escalation") already claim it exists. Restoring it, checked before
-- the procheck.rpc bypass so it applies even to RPC-mediated changes.

create or replace function public.protect_profile_privileges()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(old.username) = 'dev'
      and (new.department_id is distinct from old.department_id
           or new.role is distinct from old.role) then
    raise exception 'The Dev account is pinned to Operator and cannot be reassigned';
  end if;

  if auth.uid() is null or current_setting('procheck.rpc', true) = 'on' then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.role is distinct from old.role
     or new.department_id is distinct from old.department_id
     or new.custom_role_id is distinct from old.custom_role_id
     or new.username is distinct from old.username
     or new.email is distinct from old.email
     or new.created_at is distinct from old.created_at then
    raise exception 'Role, department and username can only be changed by an admin';
  end if;
  return new;
end;
$$;
