# Permission model

Everything here is enforced in the database (RLS, triggers, security-definer
functions). The app only decides which buttons to show. Migrations:
`20261009160000_department_roles`, `…161000_account_rules`,
`…162000_project_task_rules`, `…163000_drop_ambiguous_department_overload`
(plus `…120000_protect_operator_department`). All are applied to the live
project "ProCheck Multi-User".

## Who is who
- **Operator:** the single user in the department flagged `is_operator` (a trigger allows only one). Can do everything. Only the Operator can create, promote or remove IT managers.
- **IT:** the department flagged `is_it`. Managers and members both see all projects and can set a project's owning department, create departments, and add/promote/remove people in every other department. **IT managers** may also add/remove IT *members*. IT members may not touch IT's people.
- **Other departments:** managers and members. Cannot see other departments' projects.
- **Job titles (custom roles):** per department, created and edited by that department's managers (or IT/Operator). "Manager" is fixed and cannot be created, renamed or deleted as a title.

## Permissions a job title can carry (and nothing more)
| Flag | Lets the member | Why it is delegable |
|---|---|---|
| `create_projects` | create projects in their own department | creating is low-risk; ownership is forced to their department |
| `edit_projects` | rename/recolour/archive department projects | reversible |
| `manage_tasks` | add tasks inside department projects and assign them to department members | day-to-day planning |
| `view_team` | see the Team dashboard and department profiles | read-only |

**Always manager-only** (no flag exists): managing job titles and their permissions, promoting/demoting managers, adding/removing people, deleting projects. **Only IT/Operator:** changing a project's owning department, creating departments.

## Visibility
- **Projects:** own department; IT/Operator see all.
- **Tasks in a project:** everyone in the project's department sees them (so a check-off reaches them live); only the assignee/owner can change one, plus managers and `manage_tasks` roles. Visibility follows the project's *current* department.
- **Personal tasks (no project):** the creator, their department manager, IT and the Operator.
- **Who checked it off:** `tasks.completed_by` is set by a trigger from the signed-in user; clients cannot set it.

## Tamper-proofing
`role`, `department_id`, `custom_role_id`, `username` and `email` on `profiles` change only inside the admin functions (they set a transaction flag) or from the SQL editor. This closes a hole where an IT member could move themselves into the Operator department. Department flags (`is_operator`, `is_it`) have no insert/update policy, so only the security-definer functions create departments.

## Account & department lifecycle (Phase 4, `20261011400000_phase4_account_department_lifecycle`)
- **Deactivate/reactivate an account, reset a password, create an account:** go through the `admin-users` Edge Function (Supabase Auth Admin API — bans via `ban_duration`, never writes `auth.users` by hand). `is_admin()` to act at all; `is_operator()` to touch an account in the Operator or IT department, same split `admin_create_profile` already used. The Operator can't deactivate themself or be deactivated. Deactivating keeps the person's task/project history; `profiles.is_active = false` just drops them out of assignment pickers (`profile_directory()` and `departmentMembersProvider` both carry `is_active`).
- **Hard delete an account or department:** `admin_delete_profile`/`admin_delete_department` are now **Operator-only** (IT can no longer hard-delete), behind a typed confirmation in the UI. A department can only be hard-deleted once it has no members and no projects left.
- **Archive a department:** `admin_archive_department` (is_admin; is_operator for the Operator/IT tier) sets `departments.archived_at`, blocked while it still owns any project. Archived departments keep their members and history; IT moves projects out first with the existing owning-department action.

## Test results (each role impersonated inside a transaction that was rolled back; nothing left behind)
| Role | Action | Expected | Actual |
|---|---|---|---|
| A member (no role) | create project | denied | denied |
| A member (title-only role) | create project | denied | denied |
| A member (Senior: create_projects) | create project (client claims dept B) | ok | ok |
| server | project owner department auto-set to creator's | A | A |
| A manager | create project | ok | ok |
| B manager / B member | see dept A projects | 0 | 0 |
| IT member | see dept A projects | 2 | 2 |
| IT member | move project to dept B | ok | ok |
| B manager | sees project after IT hands it to B | 1 | 1 |
| A manager | change project's owning dept | denied | denied |
| A member (no role) | edit / delete dept project | denied | denied |
| A member (Senior) | comment on dept project | ok | ok |
| A member (Senior) | delete project | denied | denied |
| B member | comment on dept A project | denied | denied |
| A manager | create project task + assign to A member | ok | ok |
| A manager | assign task to dept B user | denied | denied |
| A member (no role) | see dept project task not assigned to them | 1 | 1 |
| A member (no role) | check off a task not assigned to them | denied | denied |
| A member (no role) | create task inside a project | denied | denied |
| B member | see dept A project task | 0 | 0 |
| A member (assignee) | check off own task, trying to spoof `completed_by` | ok | ok |
| server | `completed_by` = the real checker | yes | yes |
| A member (no role) | sees the check-off (what realtime delivers) | yes | yes |
| B member | sees the check-off (realtime must NOT reach) | 0 | 0 |
| server | `completed_by` cleared on un-check | yes | yes |
| A member | create personal task / assigned to dept B user | ok / denied | ok / denied |
| A member (Senior), (title-only) | see colleague's personal task | 0 | 0 |
| A manager | see member's personal task | 1 | 1 |
| B manager | see dept A personal task | 0 | 0 |
| IT member, Operator | see any personal task | 1 | 1 |
| A member | hand own task to a colleague | denied | denied |
| A manager | assign task to dept member | ok | ok |
| A member | make self manager / move self to Operator dept / give self a role | denied | denied |
| A member | change own display name | ok | ok |
| IT member | move self into Operator dept / make self IT manager (old hole) | denied | denied |
| A manager | promote member by editing the row / insert department / set IT flag | denied | denied |
| A manager | create role in own dept | ok | ok |
| A manager | create role named "Manager" / in dept B / move role to dept B | denied | denied |
| A manager | delete role still assigned | denied | denied |
| A manager | rename role / edit its permissions | ok | ok |
| A manager | give member a dept role | ok | ok |
| A manager | give member another dept's role / role to a dept B member | denied | denied |
| A member | create role | denied | denied |
| B manager | see dept A roles / clear role of dept A member | 0 / denied | 0 / denied |
| IT member | clear role of any dept member | ok | ok |
| A member (role with `view_team`) | read dept profiles | many | many |
| A member (title-only) | read dept profiles | 1 (self) | 1 (self) |
| A manager | add member to own dept | ok | ok |
| A manager | add manager to own dept / member to dept B | denied | denied |
| A member | add member | denied | denied |
| IT member | add member to IT | denied | denied |
| IT member | add manager to dept B | ok | ok |
| IT member | create department | ok | ok (after dropping an ambiguous overload) |
| A manager | create department | denied | denied |
| IT member | promote dept A member to manager | ok | ok |
| IT member | demote an IT manager | denied | denied |
| A manager | promote member to manager | denied | denied |
| A manager | remove a member of own dept | ok | ok |
| A manager | remove an IT manager | denied | denied |
| IT manager | add member to IT | ok | ok |
| IT manager | add IT manager | denied | denied |
| IT manager | remove IT member | ok | ok |
| Operator | add IT manager | ok | ok |
| Operator | add a second Operator user | denied | denied |
| Operator | delete own account | denied | denied |
| Operator | delete Operator department | denied | denied (0 rows) |
| Operator | see all projects | all | all |

**Not tested at the socket level:** a real Supabase Realtime subscription. Realtime applies the same SELECT policies as the rows above, which is what the "sees the check-off" / "must NOT reach" rows verify.
