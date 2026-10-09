# Multi-user cues: department, role, owner, assignee, author, actor

Status: proposal only. Nothing here is applied or implemented. Written against branch
`redesign/industrial-skeuo`. The live Supabase project "ProCheck Multi-User" was inspected
read-only (table columns and `pg_policies` only, no data rows).

## 0. Drift check (repo migrations vs live project)

- `list_migrations` shows all 14 repo migrations applied, same versions and names.
- Live `profiles`, `departments`, `projects`, `tasks` columns match the repo (incl. `username`,
  `is_operator`, `is_it`, `activity_log`/`comments` jsonb, `estimated_minutes`).
- Live policies match the latest migrations (`it_department`, `task_checkoff_project_rls`).
- Cosmetic only: the stored `profiles_select_department_as_manager` policy shows the old 6-column
  `current_profile()` signature (pre-`username`); tasks/projects policies show 7. Harmless, but it
  was never recreated after `username` was added.
- Key RLS fact for everything below: NO policy lets a plain member read any profile other than
  their own. Managers read their department's profiles; Operator/IT read all.

## 1. Current state

| Cue | DB column | Dart/Hive model | Sync | Displayed today |
|---|---|---|---|---|
| department | `profiles.department_id`, `tasks.department_id`, `projects.department_id` (NOT NULL); `departments.name/is_operator/is_it`, readable by everyone (`departments_select_authenticated`) | `Profile.departmentId` (profile.dart); `Task.departmentId` HiveField 18 (task.dart:131); `Project.departmentId` HiveField 11 (project.dart:83); `Department` (not Hive) | tasks/projects pull+push it (task.dart:337,359; project.dart:204,219); departments via departments_provider.dart | Admin People subtitle `Role . Dept` (admin_screen.dart:582-585), Dept list Operator/IT text (admin_screen.dart:501-504), Dev panel (admin_screen.dart:612). Nowhere on project/task/dashboard/sidebar |
| role | `profiles.role` enum member/manager | `Profile.role`, `isManager` (profile.dart); not Hive, fetched fresh | `currentProfileProvider` (auth_provider.dart), `departmentMembersProvider` | Team row text (team_screen.dart:126), Admin People (admin_screen.dart:582). Gates assign dropdown (task_tile.dart:630) |
| admin tier | `departments.is_operator/is_it` | `Department.isAdminTier` | departments_provider.dart | Admin dept list text only (admin_screen.dart:501) |
| owner | `tasks.owner_id`, `projects.owner_id` (nullable uuid FK profiles) | `Task.ownerId` HiveField 16 (task.dart:121), `Project.ownerId` HiveField 10 (project.dart:77) | pulled and pushed (task.dart:335,357; project.dart:203,218). Stamped at create from `_loadOwnProfile` (tasks_provider.dart:112-125); blank-owner rows are not pushed (tasks_provider.dart:160) | Not displayed anywhere; only used for the push guard |
| assignee | `tasks.assignee_id` | `Task.assigneeId` HiveField 17 (task.dart:125) | pulled+pushed; `assignTask` (tasks_provider.dart:339) | Task detail only: `_AssigneeAndEstimateRow` (task_tile.dart:622-695); Team screen counts open tasks per member (team_screen.dart:65). Projects have NO assignee column |
| comment author | none as a column: inside `projects.comments` jsonb `{id, author, text, timestamp}` | `ProjectComment.author` String (project_comment.dart:16), free-text name, not a user id | rides along in the jsonb | Text under each comment (project_detail_overlay.dart:551). Always the literal `'You'` (project_detail_overlay.dart:587) |
| activity actor | none: `projects.activity_log` jsonb `{kindIndex, description, timestamp}` | `ActivityEntry` has no actor field (activity_entry.dart); description is pre-rendered | rides along in jsonb | Description text only, e.g. `You added "..."` (tasks_provider.dart:310,325,425; projects_provider.dart:204) |

Two existing problems that affect any cue work:

1. Comments and activity are authored as "You". The jsonb syncs to the whole department
   (`projects_select`), so a teammate reads "You completed X" for someone else's action. An actor
   id must be stored with each entry (section 2).
2. `activity_log` and `comments` are whole-column jsonb arrays upserted with the project row, so two
   people commenting concurrently can overwrite each other (last write wins). This limits how
   trustworthy an "author" cue is until comments move to a table (C2).

## 2. Classification

A = frontend restyle of data already on the client. B = data in DB, client model/provider/query
change. C = schema or RLS change.

| Cue | Class | Backend needed? |
|---|---|---|
| department plate, Operator/IT variant | A | no |
| own role plate (sidebar identity, dashboard) | A | no |
| role / owner / assignee names for manager, Operator, IT viewers | A/B (client provider only) | no |
| owner / assignee / author names for members | C1 | yes (RLS or view) |
| comment author, activity actor (new entries) | B | no (jsonb) |
| robust author, concurrent comments | C2 | yes, optional |
| project assignee | C3 | yes, optional, not recommended |

Notes per cue:

- Department (A): id and name are on the client for tasks, projects and the signed-in profile;
  departments are world-readable. Needs only a Department lookup by id in a widget. Local-only rows
  have blank `departmentId` (task.dart:131).
- Role (A): own role is on `currentProfileProvider`. Other people's role is known only for profiles
  the viewer can read (section 0).
- Admin tier (A): `Department.isOperator/isIt` already loaded; plate variant = the department
  plate when `isAdminTier`.
- Owner (B, C1 for members): `ownerId` is on every row. For manager/Operator/IT,
  `departmentMembersProvider` already returns the readable profiles; add a `profilesByIdProvider`
  (Map<String, Profile>) from it (client-only provider change). A member cannot resolve the owner of
  a department project created by someone else: needs C1.
- Assignee: same split. A member only sees tasks they own or are assigned, so assignee is either
  themselves (A) or a manager-owner (name needs C1).
- Comment author / activity actor (B): stop writing `'You'`; write `displayName` plus a new optional
  `authorId` / `actorId` in the jsonb (additive Hive field, see risks). Old entries keep "You".

### Proposed SQL (NOT applied)

C1 (preferred): a narrow identity read path that omits email/username.
```sql
-- id, display_name, role, department_id only; same department, or everyone for Operator/IT.
-- Default (owner-run) view, filters itself; profiles RLS untouched.
create or replace view public.profile_directory as
select p.id, p.display_name, p.role, p.department_id
from public.profiles p
where public.is_admin()
   or p.department_id = (select department_id from public.current_profile());
grant select on public.profile_directory to authenticated;
```
C1b (simpler, NOT recommended: exposes `email`/`username`):
```sql
create policy "profiles_select_same_department" on profiles for select to authenticated
  using (department_id = (select department_id from public.current_profile()));
```
C2 (optional, later): comments as a table so author is a real FK and concurrent adds do not clobber.
```sql
create table project_comments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  author_id uuid references profiles(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now()
);
alter table project_comments enable row level security;
create policy pc_select on project_comments for select to authenticated
  using (exists (select 1 from projects pr where pr.id = project_id)); -- inherits projects_select
create policy pc_insert on project_comments for insert to authenticated
  with check (author_id = auth.uid()
              and exists (select 1 from projects pr where pr.id = project_id));
alter publication supabase_realtime add table project_comments;
```
Activity can follow the same shape (`project_activity` with `actor_id`).
C3 (skip): `alter table projects add column assignee_id uuid references profiles(id);`

## 3. UI proposals

Vocabulary: small engraved plates in neutral metal, one lamp for state. This section is a proposal only.
- Role plate: engraved `MGR` / `MBR`; manager has a lit lamp, member an unlit one.
- Department plate: abbreviated name on a plate. Operator = double-border plate with amber lamp;
  IT = plate with a bolt-head corner and teal lamp. Ordinary departments: neutral plate, optional
  hue from a hash of the id. Never encode meaning in color alone; text is always present.
- Owner badge: key glyph + initial disc; shown when owner is not the current user (mine = quiet `ME` stamp).
- Assignee chip: initial disc in a socket ring; dashed empty socket = unassigned.
- Every cue has a tooltip / semantic label; lamps are decorative.

| Screen | Proposal | Class |
|---|---|---|
| Sidebar identity (app_sidebar.dart:110-123) | Collapsed: initial disc with role lamp. Expanded: name, role plate, department plate (Operator/IT variant). Keep tap-to-confirm sign-out | A |
| Project card (project_card.dart) | Department plate in a corner; owner badge at the bottom, hidden when mine | A (dept); A/B owner for manager+; C1 for members |
| Task row (task_tile.dart, smart_view_task_row.dart) | Trailing assignee chip (empty socket when none); department plate only in cross-department views (Operator/IT) | A/B |
| Task detail (`_AssigneeAndEstimateRow`, task_tile.dart:622) | Assignee chip replaces icon+label; add "Created by [owner badge]" line; dropdown stays for managers | B |
| Comments (project_detail_overlay.dart:551) | Initial disc + display name + role plate; "You" only when `authorId == me` | B new entries; C1 for member name resolution |
| Activity (`_ActivityRow`, project_detail_overlay.dart:442) | Actor initial disc beside kind icon; description without the "You" prefix | B |
| Dashboard (dashboard_screen.dart) | Header strip with own role + department plates; for Operator/IT a per-department plate breakdown | A |
| Team (team_screen.dart:114-126) | Role plate instead of `Manager`/`Member` text; department plate when viewer is Operator/IT | A |
| Admin (admin_screen.dart:501,582) | Same plates replacing text, one vocabulary app-wide | A |

## 4. Risks

RLS visibility (live policies verified):
- Member: tasks they own or are assigned (`tasks_select`); all projects in their department
  (`projects_select`); only their own profile. Project owner/commenter names are unresolvable
  without C1.
- Manager: all tasks and profiles of own department; can assign within it.
- Operator/IT (`is_admin()`): everything including all profiles; department plates matter most here.
- `departmentMembersProvider` mirrors `profiles_select`. Keep that, and degrade to initial-only
  ("Teammate") when a profile is not readable. Do not widen the client query to compensate.

Privacy:
- Show `display_name` only. Never `email` or the `username` login credential (the `dev` account is
  special-cased, admin_screen.dart:571). The C1 view deliberately omits email.
- Names stored in comments/activity jsonb are copied to every department member and go stale after a
  rename. Prefer storing `authorId` and resolving at render, with the stored name as fallback.
- Deleted users: `owner_id` is `on delete set null`. `Task.fromSupabase` and `Project.fromSupabase`
  cast `owner_id as String` (task.dart:335, project.dart:203), so a null owner would throw on pull.
  Latent bug worth fixing regardless; render null owner as "Former member".

Offline / Hive migration:
- Additive fields: `ProjectComment.authorId` (HiveField 4) and `ActivityEntry.actorId` (HiveField 3),
  each with `defaultValue: ''`. Regenerate `.g.dart` with build_runner. Never reuse retired indexes
  (Task field 12, Project field 9 are documented as retired; Task 14 is unused).
- `fromJson` must tolerate missing keys (as the current code does for `kindIndex`).
- Mixed-version rollout: an old client re-upserting a project rewrites the whole jsonb and will drop
  keys it does not know (`authorId`/`actorId`). Ship the model change before UI depends on it.
- Profiles are not cached in Hive; offline, plates fall back to initials. Cache the directory only if
  offline cold start matters.

Performance:
- Build one `Map<String, Profile>` and `Map<String, Department>` provider and use `select` per row;
  department-sized lists are small, so no N+1.
- `profile_directory` is one extra select alongside the existing profile load.
- Keep plates cheap: const `DecoratedBox` + gradient, avoid per-row blur/shadow in long lists.

## 5. Recommended rollout

No backend change (client only):
1. Shared widgets `RolePlate`, `DepartmentPlate`, `AssigneeChip`, `OwnerBadge`, driven by
   `Profile`/`Department` (A). Use in sidebar identity, Team, Admin, Dashboard header.
2. `profilesByIdProvider` from `departmentMembersProvider` + current profile; department plate on
   project cards and task rows; assignee chip on task rows; owner badge for manager/Operator/IT
   viewers; graceful fallback for unreadable ids.
3. Stop baking "You" into new comments/activity (B): write `displayName` + `authorId`/`actorId`;
   render "You" only when the id is mine. Additive Hive fields, regenerate adapters.
4. Make `owner_id` null-safe in `fromSupabase`.

Needs a backend change (separate reviewed PR, applied by the project owner):
5. C1 `profile_directory` so members can see owner/assignee/author names; then enable step 2 cues
   for all roles.
6. Optional C2 comments (and activity) tables once concurrent overwrites matter.

Not recommended: C3 project assignee, C1b profile policy.
