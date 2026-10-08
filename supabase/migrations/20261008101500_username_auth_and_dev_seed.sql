-- Thomas asked (2026-10-08) to drop email from the UI entirely: ProCheck is
-- username/password only. Supabase Auth still needs an email under the
-- hood, so the app maps each username to a synthetic
-- `<username>@procheck.local` address (see
-- lib/providers/auth_provider.dart's emailForUsername) — nothing is ever
-- sent to it. For that to work for real sign-ups, "Confirm email" MUST be
-- turned off in the Supabase dashboard (Authentication > Providers >
-- Email) — a synthetic address can never receive a confirmation mail, so
-- leaving it on would lock every new sign-up out. This migration can't
-- flip that setting itself; it's a dashboard-only toggle.

-- ----- profiles: a username people actually see/sign in with -----

alter table profiles add column username text;

update profiles set username = split_part(email, '@', 1) where username is null;

alter table profiles alter column username set not null;
alter table profiles add constraint profiles_username_key unique (username);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
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

-- ----- Permanent "Dev" Operator account, for Thomas to verify operations -----
--
-- ** DEV/TESTING ONLY — "testing" is a deliberately weak password. Remove
-- this account (or at least change its password) before any real
-- company rollout. **
--
-- Inserting straight into auth.users/auth.identities isn't a documented
-- Supabase API — it relies on the current GoTrue schema shape (tested
-- against the schema as of this migration). If it errors, the shape may
-- have changed; use Authentication > Add user in the dashboard instead
-- (username "Dev", password "testing", then run the two UPDATE
-- statements at the bottom by hand) and let me know so I can fix this
-- migration.
--
-- Guarded with `where not exists (...)` rather than `on conflict` —
-- auth.users.email is only unique via a partial index (scoped to
-- non-SSO users), which `on conflict (email)` can't target directly.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
select
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'dev@procheck.local',
  crypt('testing', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"username":"Dev","display_name":"Dev"}'::jsonb,
  now(), now(), '', '', '', ''
where not exists (select 1 from auth.users where email = 'dev@procheck.local');

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(),
  u.id,
  u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email),
  'email',
  now(), now(), now()
from auth.users u
where u.email = 'dev@procheck.local'
  and not exists (
    select 1 from auth.identities i
    where i.provider = 'email' and i.provider_id = u.id::text
  );

-- The on_auth_user_created trigger (above) creates Dev's profiles row
-- automatically with role defaulting to 'member' and no department — fix
-- both up so Dev reads as a manager inside the Operator department (the
-- is_operator() bypass means the department alone would already see
-- everything via RLS, but the app's own manager-only UI, like the
-- assignee picker, keys off role rather than department).
update profiles
set role = 'manager',
    department_id = (select id from departments where is_operator)
where id = (select id from auth.users where email = 'dev@procheck.local');
