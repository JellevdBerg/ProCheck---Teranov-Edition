-- Who may create / delete accounts and change roles, enforced server-side.
-- These functions are the only way to change a profile's role, department or
-- custom role (see protect_profile_privileges).
--
-- Operator: everything, except there is exactly one Operator account.
-- IT manager: add/remove IT members; everything IT can do.
-- IT member: everything IT can do except touch the IT department's people.
-- IT (any): create departments (existing), add managers and members to any
--   department other than Operator/IT, promote/demote managers there.
-- Department manager: add/remove MEMBERS of their own department, hand out
--   that department's custom roles. Cannot make managers.
-- Only the Operator can create, promote or remove IT managers.

create or replace function public.admin_create_profile(
  p_username text, p_password text, p_display_name text,
  p_role text default 'member', p_department_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  dept public.departments;
  new_user_id uuid;
  synthetic_email text;
  clean_username text;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then raise exception 'Not signed in'; end if;

  select * into dept from public.departments where id = p_department_id;
  if dept.id is null then raise exception 'Pick a department'; end if;
  if p_role not in ('member', 'manager') then
    raise exception 'role must be ''member'' or ''manager''';
  end if;
  if dept.is_operator then
    raise exception 'The Operator department has exactly one user';
  end if;

  if public.is_operator() then
    null;
  elsif dept.is_it then
    if not public.is_it_manager() then
      raise exception 'Only the Operator or an IT manager can add IT accounts';
    end if;
    if p_role = 'manager' then
      raise exception 'Only the Operator can assign IT managers';
    end if;
  elsif public.is_admin() then
    null;
  elsif me.role = 'manager' and me.department_id = dept.id then
    if p_role <> 'member' then
      raise exception 'Managers can add members only';
    end if;
  else
    raise exception 'You are not allowed to create accounts in this department';
  end if;

  clean_username := lower(trim(p_username));
  if length(clean_username) = 0 then raise exception 'Username cannot be empty'; end if;
  if length(p_password) < 6 then raise exception 'Password must be at least 6 characters'; end if;
  if exists (select 1 from public.profiles where username = clean_username) then
    raise exception 'Username "%" is already taken', clean_username;
  end if;

  synthetic_email := clean_username || '@procheck.local';
  new_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated',
    synthetic_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', clean_username, 'display_name', trim(p_display_name)),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), new_user_id, new_user_id::text,
    jsonb_build_object('sub', new_user_id::text, 'email', synthetic_email),
    'email', now(), now(), now()
  );

  perform set_config('procheck.rpc', 'on', true);
  update public.profiles
     set role = p_role::user_role, department_id = dept.id
   where id = new_user_id;

  return new_user_id;
end;
$$;

create or replace function public.admin_delete_profile(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  target public.profiles;
  tdept public.departments;
begin
  select * into me from public.profiles where id = auth.uid();
  select * into target from public.profiles where id = p_user_id;
  if target.id is null then raise exception 'Account not found'; end if;
  select * into tdept from public.departments where id = target.department_id;

  if p_user_id = auth.uid() then raise exception 'Cannot delete your own account'; end if;
  if lower(target.username) = 'dev' then raise exception 'The Dev account cannot be deleted'; end if;
  if coalesce(tdept.is_operator, false) then
    raise exception 'The Operator account cannot be deleted';
  end if;

  if public.is_operator() then
    null;
  elsif coalesce(tdept.is_it, false) then
    if not (public.is_it_manager() and target.role = 'member') then
      raise exception 'Only the Operator can remove IT managers; IT managers can remove IT members';
    end if;
  elsif public.is_admin() then
    null;
  elsif me.role = 'manager' and me.department_id = target.department_id and target.role = 'member' then
    null;
  else
    raise exception 'You are not allowed to delete this account';
  end if;

  delete from auth.users where id = p_user_id;
end;
$$;

-- Promote a member to manager, or demote a manager to member.
create or replace function public.set_user_role(p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare
  target public.profiles;
  tdept public.departments;
begin
  if p_role not in ('member', 'manager') then
    raise exception 'role must be ''member'' or ''manager''';
  end if;
  select * into target from public.profiles where id = p_user_id;
  if target.id is null then raise exception 'Account not found'; end if;
  select * into tdept from public.departments where id = target.department_id;

  if p_user_id = auth.uid() then raise exception 'You cannot change your own role'; end if;
  if lower(target.username) = 'dev' or coalesce(tdept.is_operator, false) then
    raise exception 'That account''s role is fixed';
  end if;

  if coalesce(tdept.is_it, false) then
    if not public.is_operator() then
      raise exception 'Only the Operator can assign or remove IT managers';
    end if;
  elsif not public.is_admin() then
    raise exception 'Only IT or the Operator can assign or remove managers';
  end if;

  perform set_config('procheck.rpc', 'on', true);
  update public.profiles set role = p_role::user_role where id = p_user_id;
end;
$$;

-- Give a member a job title (or clear it with null).
create or replace function public.set_member_role(p_user_id uuid, p_role_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  target public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  select * into target from public.profiles where id = p_user_id;
  if target.id is null then raise exception 'Account not found'; end if;
  if target.role <> 'member' then raise exception 'Only members can have a job title'; end if;

  if not (public.is_admin()
          or (me.role = 'manager' and me.department_id = target.department_id)) then
    raise exception 'You are not allowed to change this person''s role';
  end if;
  if p_role_id is not null and not exists (
       select 1 from public.department_roles r
       where r.id = p_role_id and r.department_id = target.department_id) then
    raise exception 'That role belongs to another department';
  end if;

  perform set_config('procheck.rpc', 'on', true);
  update public.profiles set custom_role_id = p_role_id where id = p_user_id;
end;
$$;

revoke execute on function public.set_user_role(uuid, text) from public, anon;
revoke execute on function public.set_member_role(uuid, uuid) from public, anon;
grant execute on function public.set_user_role(uuid, text) to authenticated;
grant execute on function public.set_member_role(uuid, uuid) to authenticated;
revoke execute on function public.admin_create_profile(text, text, text, text, uuid) from public, anon;
revoke execute on function public.admin_delete_profile(uuid) from public, anon;
