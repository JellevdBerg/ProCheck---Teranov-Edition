-- Thomas asked (2026-10-08) to make sure the Dev account always stays in
-- the Operator department. Checking how that could ever change surfaced
-- a real gap, not just a Dev-specific one: `profiles_update_own` (from
-- 20261001091500_rls_policies.sql) lets anyone update their own profile
-- row with no column restriction at all — `role` and `department_id`
-- included. RLS's `with check` can't compare against the row's previous
-- value, so the fix is a trigger, not a tighter policy.
--
-- (Confirmed nothing in the app actually relies on self-service profile
-- updates today — nothing in lib/ calls `.update()` on `profiles` at
-- all — so tightening this changes no current behavior.)

create function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The Dev account is a permanent fixture of the Operator department
  -- (see 20261008101500_username_auth_and_dev_seed.sql) for verifying
  -- role behavior — pinned even against an admin-authored change, not
  -- just self-service ones. If it ever genuinely needs to move, drop
  -- this trigger (or this username check) first.
  if old.username = 'dev' then
    if new.department_id is distinct from old.department_id
        or new.role is distinct from old.role then
      raise exception 'The Dev account is pinned to Operator and cannot be reassigned';
    end if;
  end if;

  -- Everyone else: role/department changes are an admin-tier action
  -- (admin_create_profile already enforces this on creation) — a plain
  -- self-update, like `profiles_update_own` allows, may not touch them.
  if not public.is_admin() then
    if new.role is distinct from old.role
        or new.department_id is distinct from old.department_id then
      raise exception 'Only an Operator or IT can change role or department';
    end if;
  end if;

  return new;
end;
$$;

create trigger protect_profile_privileges_trigger
  before update on profiles
  for each row execute function public.protect_profile_privileges();
