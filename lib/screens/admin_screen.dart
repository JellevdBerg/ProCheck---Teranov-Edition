import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/latest_migration.dart';
import '../data/supabase_config.dart';
import '../models/department.dart';
import '../models/profile.dart';
import '../providers/admin_provider.dart';
import '../providers/app_info_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_members_provider.dart';
import '../providers/departments_provider.dart';
import '../providers/sync_log_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/blurred_dialog.dart';

/// Operator/IT-only: create departments and user accounts. Reachable only
/// from the sidebar's Admin nav item, itself gated on [isAdminProvider] —
/// but the real access control is server-side (every RPC this screen
/// calls re-checks `is_admin()`/`is_operator()` itself), so this screen
/// being visible is a convenience, not a permission grant. [isOperatorProvider]
/// additionally gates the handful of actions only Operator (not IT) can
/// do — marking a department as IT, and placing an account into Operator
/// or IT itself.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;
    final departmentsAsync = ref.watch(departmentsProvider);
    final peopleAsync = ref.watch(departmentMembersProvider);
    final isOperator = ref.watch(isOperatorProvider).valueOrNull ?? false;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Admin', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Create departments and accounts for the company.',
            style: TextStyle(color: tokens.neutral500),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    title: 'Departments',
                    actionLabel: 'New department',
                    onAction: () => _createDepartment(
                      context,
                      ref,
                      isOperator: isOperator,
                      hasItDepartment:
                          departmentsAsync.valueOrNull?.any((d) => d.isIt) ??
                          false,
                    ),
                  ),
                  const SizedBox(height: 8),
                  departmentsAsync.when(
                    loading: () =>
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: LinearProgressIndicator(),
                        ),
                    error: (error, _) => Text('Could not load departments: $error'),
                    data: (departments) => _DepartmentList(departments: departments),
                  ),
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'People',
                    actionLabel: 'New account',
                    onAction: () => _createAccount(
                      context,
                      ref,
                      departmentsAsync.valueOrNull ?? const [],
                      isOperator: isOperator,
                    ),
                  ),
                  const SizedBox(height: 8),
                  peopleAsync.when(
                    loading: () =>
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: LinearProgressIndicator(),
                        ),
                    error: (error, _) => Text('Could not load people: $error'),
                    data: (people) => _PeopleList(
                      people: people,
                      departments: departmentsAsync.valueOrNull ?? const [],
                    ),
                  ),
                  if (isOperator) ...[
                    const SizedBox(height: 32),
                    const _DevPanel(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createDepartment(
    BuildContext context,
    WidgetRef ref, {
    required bool isOperator,
    required bool hasItDepartment,
  }) async {
    final result = await _showNewDepartmentDialog(
      context,
      // Only Operator can mark a department IT, and only while none
      // exists yet — the backend enforces both, this just avoids
      // offering a checkbox that would be refused.
      offerItCheckbox: isOperator && !hasItDepartment,
    );
    if (result == null) return;

    try {
      await ref
          .read(adminControllerProvider)
          .createDepartment(result.name, isIt: result.isIt);
      ref.invalidate(departmentsProvider);
    } on AuthException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  Future<void> _createAccount(
    BuildContext context,
    WidgetRef ref,
    List<Department> departments, {
    required bool isOperator,
  }) async {
    // IT can create accounts in any ordinary department, but — same as
    // the backend's own check — not into Operator or IT itself.
    final selectableDepartments = isOperator
        ? departments
        : departments.where((d) => !d.isAdminTier).toList();

    final result = await _showNewAccountDialog(context, selectableDepartments);
    if (result == null) return;

    try {
      await ref.read(adminControllerProvider).createAccount(
        username: result.username,
        password: result.password,
        displayName: result.displayName,
        role: result.role,
        departmentId: result.departmentId,
      );
      ref.invalidate(departmentMembersProvider);
    } on AuthException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _NewDepartmentResult {
  _NewDepartmentResult({required this.name, required this.isIt});

  final String name;
  final bool isIt;
}

Future<_NewDepartmentResult?> _showNewDepartmentDialog(
  BuildContext context, {
  required bool offerItCheckbox,
}) {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  var isIt = false;

  return showBlurredDialog<_NewDepartmentResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('New department'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                    ? 'Enter a department name'
                    : null,
              ),
              if (offerItCheckbox) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: isIt,
                  onChanged: (value) => setState(() => isIt = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Make this the IT department'),
                  subtitle: const Text(
                    'Same company-wide access as Operator, except '
                    'creating/assigning into Operator or IT.',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(
                _NewDepartmentResult(
                  name: nameController.text.trim(),
                  isIt: isIt,
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}

class _NewAccountResult {
  _NewAccountResult({
    required this.username,
    required this.password,
    required this.displayName,
    required this.role,
    required this.departmentId,
  });

  final String username;
  final String password;
  final String displayName;
  final String role;
  final String? departmentId;
}

Future<_NewAccountResult?> _showNewAccountDialog(
  BuildContext context,
  List<Department> departments,
) {
  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final displayNameController = TextEditingController();
  var role = 'member';
  String? departmentId;

  return showBlurredDialog<_NewAccountResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final selectedDepartment = departments
            .where((d) => d.id == departmentId)
            .firstOrNull;
        final forcedManager = selectedDepartment?.isAdminTier ?? false;

        return AlertDialog(
          title: const Text('New account'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: displayNameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  autocorrect: false,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Enter a username' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (value) =>
                      (value == null || value.length < 6) ? 'At least 6 characters' : null,
                ),
                const SizedBox(height: 12),
                if (forcedManager)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text('Role: Manager (forced for Operator/IT)'),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('Member')),
                      DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    ],
                    onChanged: (value) => setState(() => role = value ?? 'member'),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: departmentId,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final department in departments)
                      DropdownMenuItem(
                        value: department.id,
                        child: Text(department.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => departmentId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(context).pop(
                  _NewAccountResult(
                    username: usernameController.text.trim(),
                    password: passwordController.text,
                    displayName: displayNameController.text.trim(),
                    role: forcedManager ? 'manager' : role,
                    departmentId: departmentId,
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        TextButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add, size: 18),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _DepartmentList extends StatelessWidget {
  const _DepartmentList({required this.departments});

  final List<Department> departments;

  @override
  Widget build(BuildContext context) {
    if (departments.isEmpty) return const Text('No departments yet.');
    return Column(
      children: [
        for (final department in departments)
          ListTile(
            dense: true,
            leading: const Icon(Icons.apartment_outlined),
            title: Text(department.name),
            trailing: department.isOperator
                ? const Text('Operator')
                : department.isIt
                ? const Text('IT')
                : null,
          ),
      ],
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.people, required this.departments});

  final List<Profile> people;
  final List<Department> departments;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const Text('No one else yet.');
    return Column(
      children: [
        for (final person in people)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              child: Text(
                person.displayName.isEmpty
                    ? '?'
                    : person.displayName[0].toUpperCase(),
              ),
            ),
            title: Text(person.displayName),
            subtitle: Text('@${person.username}'),
            trailing: Text(_departmentLabel(person, departments)),
          ),
      ],
    );
  }

  String _departmentLabel(Profile person, List<Department> departments) {
    final roleLabel = person.isManager ? 'Manager' : 'Member';
    final department = departments.where((d) => d.id == person.departmentId);
    if (department.isEmpty) return roleLabel;
    return '$roleLabel · ${department.first.name}';
  }
}

/// Operator-only (not shown to IT) — developer-facing state that's cheap
/// to read and useful for checking "is this build actually talking to the
/// right project, as the right user, and is anything failing to sync":
/// app version, which Supabase project this build points at and whether
/// its realtime socket is actually connected, the signed-in user's own
/// id/role/department, the newest migration this code shipped with, and
/// recent sync errors (see [syncLogProvider] — mirror writes and pulls
/// have always failed silently by design; this just surfaces that log
/// rather than changing the behavior).
class _DevPanel extends ConsumerWidget {
  const _DevPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;
    final packageInfo = ref.watch(packageInfoProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
    final people = ref.watch(departmentMembersProvider).valueOrNull ?? const [];
    final syncLog = ref.watch(syncLogProvider);
    final userId = supabase.auth.currentUser?.id;

    final departmentName = departments
        .where((d) => d.id == profile?.departmentId)
        .firstOrNull
        ?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Developer', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _DevRow(
          label: 'App version',
          value: packageInfo.when(
            data: (info) => '${info.version}+${info.buildNumber}',
            loading: () => '…',
            error: (_, _) => 'unknown',
          ),
        ),
        _DevRow(label: 'Supabase project', value: supabaseUrl),
        _DevRow(
          label: 'Realtime',
          value: supabase.realtime.isConnected ? 'connected' : 'disconnected',
        ),
        _DevRow(label: 'User id', value: userId ?? '—'),
        _DevRow(
          label: 'Role / department',
          value: profile == null
              ? '—'
              : '${profile.isManager ? 'manager' : 'member'} / '
                    '${departmentName ?? 'none'}',
        ),
        _DevRow(
          label: 'Last sync',
          value: syncLog.lastSyncAt?.toLocal().toString() ?? 'never',
        ),
        _DevRow(label: 'Latest migration', value: latestMigration),
        _DevRow(label: 'Accounts', value: '${people.length}'),
        _DevRow(label: 'Departments', value: '${departments.length}'),
        const SizedBox(height: 12),
        Text(
          'Accounts by department',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        if (departments.isEmpty)
          Text('None.', style: TextStyle(color: tokens.neutral500))
        else
          for (final department in departments)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${department.name}: '
                '${people.where((p) => p.departmentId == department.id).length}',
                style: TextStyle(fontSize: 12, color: tokens.neutral500),
              ),
            ),
        const SizedBox(height: 12),
        Text(
          'Recent sync errors',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        if (syncLog.entries.isEmpty)
          Text('None.', style: TextStyle(color: tokens.neutral500))
        else
          for (final entry in syncLog.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.at.toLocal()} · ${entry.source}/${entry.action} · '
                '${entry.message}',
                style: TextStyle(fontSize: 12, color: tokens.neutral500),
              ),
            ),
      ],
    );
  }
}

class _DevRow extends StatelessWidget {
  const _DevRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: TextStyle(color: tokens.neutral500)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
