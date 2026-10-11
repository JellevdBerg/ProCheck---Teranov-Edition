-- P1 #5: public self-signup had no DB-level backstop — the only
-- protection was a Supabase dashboard toggle (Authentication > Providers
-- > Email > "Enable email signup") the README asks you to flip off by
-- hand. handle_new_user() created a profiles row for ANY insert into
-- auth.users, admin-provisioned or not, so a direct supabase.auth.signUp()
-- call got a working account even with the toggle left on.
--
-- Fix: admin_create_profile now stamps a marker in the new auth user's
-- raw_app_meta_data (a column only a security-definer function —  never
-- the client — can set); handle_new_user() rejects any auth.users insert
-- missing that marker, aborting the whole signup transaction.
--
-- Also fixes P1 #6 while touching this function: the duplicate-username
-- check compared the (lower-cased) candidate against the stored username
-- as-is, missing the mixed-case seeded "Dev" account — "dev"/"DEV" could
-- be created alongside it. Now compares lower(username) on both sides.

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
  -- lower(username): the seeded "Dev" account's username was inserted with
  -- its original case (P1 #6) — compare case-insensitively so "dev"/"DEV"
  -- are still caught as the same name, not just rows already stored
  -- lowercase.
  if exists (select 1 from public.profiles where lower(username) = clean_username) then
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
    '{"provider":"email","providers":["email"],"procheck_provisioned":true}'::jsonb,
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

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.raw_app_meta_data ->> 'procheck_provisioned', 'false') <> 'true' then
    raise exception 'Self-service sign-up is disabled for ProCheck — accounts are created by an administrator';
  end if;
  insert into public.profiles (id, email, username, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.email)
  );
  return new;
end;
$$;

revoke execute on function public.admin_create_profile(text, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_create_profile(text, text, text, text, uuid) to authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
