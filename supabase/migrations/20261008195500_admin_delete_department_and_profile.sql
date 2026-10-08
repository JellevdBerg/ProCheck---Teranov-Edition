-- Thomas asked (2026-10-08) to be able to remove departments and
-- individuals, and for IT to have the same privilege as Operator —
-- mirrors the existing admin_create_department/admin_create_profile
-- pattern: both are SECURITY DEFINER RPCs gated on is_admin() (Operator
-- or IT), with the same Operator-only carve-out for the Operator/IT
-- department tier that creation already has.

create function public.admin_delete_department(p_department_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_is_admin_tier boolean;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can delete departments';
  end if;

  target_is_admin_tier := coalesce(
    (select d.is_operator or d.is_it from public.departments d where d.id = p_department_id),
    false
  );
  if target_is_admin_tier and not public.is_operator() then
    raise exception 'Only an Operator can delete the Operator or IT department';
  end if;

  -- profiles.department_id is ON DELETE SET NULL, so members of the
  -- deleted department are kept, just unassigned, rather than blocked
  -- or cascaded away.
  delete from public.departments where id = p_department_id;
end;
$$;

revoke all on function public.admin_delete_department(uuid) from public;
grant execute on function public.admin_delete_department(uuid) to authenticated;

create function public.admin_delete_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_username text;
  target_is_admin_tier boolean;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can delete accounts';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Cannot delete your own account';
  end if;

  select p.username, (d.is_operator or d.is_it)
    into target_username, target_is_admin_tier
  from public.profiles p
  left join public.departments d on d.id = p.department_id
  where p.id = p_user_id;

  if target_username is null then
    raise exception 'Account not found';
  end if;
  if lower(target_username) = 'dev' then
    raise exception 'The Dev account cannot be deleted';
  end if;
  if coalesce(target_is_admin_tier, false) and not public.is_operator() then
    raise exception 'Only an Operator can delete an account in the Operator or IT department';
  end if;

  -- profiles.id references auth.users.id ON DELETE CASCADE, so removing
  -- the auth user removes the profile too.
  delete from auth.users where id = p_user_id;
end;
$$;

revoke all on function public.admin_delete_profile(uuid) from public;
grant execute on function public.admin_delete_profile(uuid) to authenticated;
