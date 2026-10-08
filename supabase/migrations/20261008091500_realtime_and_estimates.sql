-- Adds a per-task time estimate (minutes) for the team dashboard's
-- occupancy view, and enables Postgres Changes realtime on tasks/projects
-- so a teammate's edit shows up live instead of only on next launch.

alter table tasks add column estimated_minutes integer;

alter publication supabase_realtime add table tasks;
alter publication supabase_realtime add table projects;
