-- First real account-creation attempt (2026-10-08, after the earlier
-- schema-cache 404 was fixed) hit a new error: "function gen_salt(unknown)
-- does not exist". `admin_create_profile` sets `search_path = public`
-- (needed so its own `is_admin()`/unqualified table references resolve
-- safely), but on this project pgcrypto's `crypt`/`gen_salt` live in the
-- `extensions` schema, not `public` — so the narrowed search path hid
-- them. The Dev-seed migration's own `crypt(...)` call never hit this
-- because it runs as a plain top-level statement, not inside a function
-- with its own `search_path`. Schema-qualifying both calls fixes it
-- without widening the function's search path.

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
  target_is_admin_tier boolean;
  effective_role text;
begin
  if not public.is_admin() then
    raise exception 'Only an Operator or IT can create accounts';
  end if;

  target_is_admin_tier := coalesce(
    (select d.is_operator or d.is_it from public.departments d where d.id = p_department_id),
    false
  );
  if target_is_admin_tier and not public.is_operator() then
    raise exception 'Only an Operator can create accounts in the Operator or IT department';
  end if;

  effective_role := case when target_is_admin_tier then 'manager' else p_role end;
  if effective_role not in ('member', 'manager') then
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
    extensions.crypt(p_password, extensions.gen_salt('bf')),
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

  update public.profiles
  set role = effective_role::user_role,
      department_id = p_department_id
  where id = new_user_id;

  return new_user_id;
end;
$$;
