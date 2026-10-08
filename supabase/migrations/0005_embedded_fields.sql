-- Rounds out the schema with the embedded fields the Flutter models already
-- serialize via toJson/fromJson (Subtask, Attachment, ActivityEntry,
-- ProjectComment) so the provider rewrite can store them as-is rather than
-- normalizing into their own tables for this pass. Kept as jsonb rather
-- than relational since none of them are queried independently of their
-- parent task/project, and this mirrors how they're already embedded in
-- the local Hive records.

alter table tasks add column subtasks jsonb not null default '[]'::jsonb;
alter table tasks add column attachments jsonb not null default '[]'::jsonb;
alter table tasks add column template_id uuid;

alter table projects add column activity_log jsonb not null default '[]'::jsonb;
alter table projects add column comments jsonb not null default '[]'::jsonb;
