-- Fix: admin account creation failed with "Self-service sign-up is disabled".
--
-- 20261010090000 made handle_new_user() (AFTER INSERT on auth.users) reject
-- rows missing raw_app_meta_data.procheck_provisioned. GoTrue's admin
-- createUser inserts the user first and only then applies app_metadata with
-- a follow-up UPDATE in the same transaction, so the insert-time check always
-- saw no marker and aborted every Auth-API account creation (the SQL
-- admin_create_profile path stamps the marker in the INSERT, so it worked).
--
-- Move the check to a deferred constraint trigger: it runs at commit and reads
-- the row's final state. Direct signUp() never gets the marker (clients cannot
-- set app_metadata), so it is still rejected and the transaction rolled back.

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

create or replace function public.require_provisioned_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1 from auth.users u
    where u.id = new.id
      and coalesce(u.raw_app_meta_data ->> 'procheck_provisioned', 'false') = 'true'
  ) then
    raise exception 'Self-service sign-up is disabled for ProCheck — accounts are created by an administrator';
  end if;
  return null;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.require_provisioned_user() from public, anon, authenticated;

drop trigger if exists require_provisioned_user_trigger on auth.users;
create constraint trigger require_provisioned_user_trigger
  after insert on auth.users
  deferrable initially deferred
  for each row execute function public.require_provisioned_user();
