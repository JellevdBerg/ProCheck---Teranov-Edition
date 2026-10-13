-- Public-read bucket the release workflow publishes app builds into
-- (latest.json + versioned zips). Anyone can download; only the service
-- role (the release workflow's secret) can write — no storage.objects
-- insert/update/delete policy exists for anon/authenticated.
insert into storage.buckets (id, name, public, file_size_limit)
values ('updates', 'updates', true, 209715200)
on conflict (id) do nothing;
