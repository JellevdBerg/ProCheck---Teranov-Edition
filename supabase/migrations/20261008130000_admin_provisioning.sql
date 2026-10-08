-- Thomas asked (2026-10-08) for Operators to create departments and user
-- accounts themselves, instead of doing it by hand in the Supabase
-- dashboard. Both need elevated rights the publishable/anon key can't
-- have (creating a department bypasses departments' RLS, which has no
-- insert policy; creating an account means writing into auth.users), so
-- both are exposed as SECURITY DEFINER functions the app calls via
-- `supabase.rpc(...)`, each gated on `is_operator()` so only the Operator
-- department can actually use them — the RLS/grant setup around them is
-- the real access control, not the Flutter-side nav gating.

-- ----- departments: every signed-in user can read the list (existing
-- policy), only an Operator can add to it -----

create or replace function public.admin_create_department(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can create departments';
  end if;
  if length(trim(p_name)) = 0 then
    raise exception 'Department name cannot be empty';
  end if;

  insert into public.departments (name) values (trim(p_name))
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.admin_create_department(text) from public;
grant execute on function public.admin_create_department(text) to authenticated;

-- ----- profiles: an Operator can create a new account directly (same
-- auth.users/auth.identities insert pattern as the "Dev" seed migration —
-- see its comments for why this relies on the current GoTrue schema
-- shape and the dashboard fallback if it ever breaks) -----

create or replace function public.admin_create_profile(
  p_username text,
  p_password text,
  p_display_name text,
  p_role text default 'member',
  p_department_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_user_id uuid;
  synthetic_email text;
  clean_username text;
begin
  if not public.is_operator() then
    raise exception 'Only an Operator can create accounts';
  end if;
  if p_role not in ('member', 'manager') then
    raise exception 'role must be ''member'' or ''manager''';
  end if;

  clean_username := lower(trim(p_username));
  if length(clean_username) = 0 then
    raise exception 'Username cannot be empty';
  end if;
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
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
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    synthetic_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', clean_username, 'display_name', trim(p_display_name)),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(),
    new_user_id,
    new_user_id::text,
    jsonb_build_object('sub', new_user_id::text, 'email', synthetic_email),
    'email',
    now(), now(), now()
  );

  -- on_auth_user_created already created the profiles row (role='member',
  -- no department) by the time this statement runs — fix both up to what
  -- was actually asked for.
  update public.profiles
  set role = p_role::user_role,
      department_id = p_department_id
  where id = new_user_id;

  return new_user_id;
end;
$$;

revoke all on function public.admin_create_profile(text, text, text, text, uuid) from public;
grant execute on function public.admin_create_profile(text, text, text, text, uuid) to authenticated;

-- ----- profiles: close a visibility gap found while building this —
-- is_operator() already bypasses tasks/projects RLS, but profiles had no
-- matching policy, so an Operator could only see people in their own
-- department (the same as a manager), not the whole company. The admin
-- screen needs to list everyone to manage them. -----

create policy "profiles_select_as_operator"
  on profiles for select
  to authenticated
  using (public.is_operator());
