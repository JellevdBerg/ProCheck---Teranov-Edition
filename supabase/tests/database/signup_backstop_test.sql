-- pgTAP tests for the self-signup backstop (migration
-- 20261013193830_signup_backstop_deferred_check): an auth.users row without
-- the procheck_provisioned marker is rejected, a provisioned one is accepted.
-- The check is a deferred constraint trigger, so fire it immediately here.
--
-- Run with: supabase test db (see supabase/tests/README.md).
begin;
select plan(2);

set constraints all immediate;

select throws_ok(
  $$insert into auth.users (instance_id, id, aud, role, email)
    values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),
            'authenticated', 'authenticated', 'self-signup@procheck.local')$$,
  'P0001',
  null,
  'a self-service signup (no provisioned marker) is rejected'
);

select lives_ok(
  $$insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
    values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),
            'authenticated', 'authenticated', 'provisioned@procheck.local',
            '{"procheck_provisioned":true}'::jsonb)$$,
  'an admin-provisioned account is accepted'
);

select * from finish();
rollback;
