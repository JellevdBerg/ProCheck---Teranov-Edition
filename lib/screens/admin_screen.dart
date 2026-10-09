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
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';
import '../widgets/people_plates.dart';

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
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, _) => PanelNotice(
                      'Could not load departments: $error',
                      isError: true,
                    ),
                    data: (departments) => _DepartmentList(
                      departments: departments,
                      isOperator: isOperator,
                      onDelete: (department) =>
                          _deleteDepartment(context, ref, department),
                    ),
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
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, _) => PanelNotice(
                      'Could not load people: $error',
                      isError: true,
                    ),
                    data: (people) => _PeopleList(
                      people: people,
                      departments: departmentsAsync.valueOrNull ?? const [],
                      isOperator: isOperator,
                      currentUserId: supabase.auth.currentUser?.id,
                      onDelete: (person) =>
                          _deleteAccount(context, ref, person),
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
      await ref
          .read(adminControllerProvider)
          .createAccount(
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

  Future<void> _deleteDepartment(
    BuildContext context,
    WidgetRef ref,
    Department department,
  ) async {
    final confirmed = await _confirmDelete(
      context,
      title: 'Delete department?',
      message:
          'This removes "${department.name}". Its members stay, just '
          'unassigned.',
    );
    if (!confirmed) return;

    try {
      await ref.read(adminControllerProvider).deleteDepartment(department.id);
      ref.invalidate(departmentsProvider);
      ref.invalidate(departmentMembersProvider);
    } on AuthException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  Future<void> _deleteAccount(
    BuildContext context,
    WidgetRef ref,
    Profile person,
  ) async {
    final confirmed = await _confirmDelete(
      context,
      title: 'Delete account?',
      message: 'This permanently removes @${person.username}.',
    );
    if (!confirmed) return;

    try {
      await ref.read(adminControllerProvider).deleteAccount(person.id);
      ref.invalidate(departmentMembersProvider);
    } on AuthException catch (e) {
      if (context.mounted) _showError(context, e.message);
    }
  }

  Future<bool> _confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final confirmed = await showBlurredDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          NocturneButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NocturneButton(
            label: 'Delete',
            variant: NocturneButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                validator: (value) => (value == null || value.trim().isEmpty)
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
          NocturneButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          NocturneButton(
            label: 'Create',
            variant: NocturneButtonVariant.primary,
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(
                _NewDepartmentResult(
                  name: nameController.text.trim(),
                  isIt: isIt,
                ),
              );
            },
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
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter a name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  autocorrect: false,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter a username'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (value) => (value == null || value.length < 6)
                      ? 'At least 6 characters'
                      : null,
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
                      DropdownMenuItem(
                        value: 'manager',
                        child: Text('Manager'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => role = value ?? 'member'),
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
            NocturneButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(),
            ),
            NocturneButton(
              label: 'Create',
              variant: NocturneButtonVariant.primary,
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
        StampLabel(title, size: 15),
        NocturneButton(
          label: actionLabel,
          icon: Icons.add,
          dense: true,
          onPressed: onAction,
        ),
      ],
    );
  }
}

class _DepartmentList extends StatelessWidget {
  const _DepartmentList({
    required this.departments,
    required this.isOperator,
    required this.onDelete,
  });

  final List<Department> departments;
  final bool isOperator;
  final ValueChanged<Department> onDelete;

  @override
  Widget build(BuildContext context) {
    if (departments.isEmpty) return const PanelNotice('No departments yet.');
    return PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < departments.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _row(context, departments[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Department department) {
    final tokens = context.nocturne;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.apartment_outlined, color: tokens.neutral400),
          const SizedBox(width: 12),
          Expanded(child: Text(department.name)),
          if (department.isOperator)
            const DepartmentPlate(name: 'Operator', isOperator: true)
          else if (department.isIt)
            const DepartmentPlate(name: 'IT', isIt: true),
          // Only an Operator can remove the Operator/IT department
          // itself — same asymmetry as creating one.
          if (isOperator || !department.isAdminTier)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => onDelete(department),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({
    required this.people,
    required this.departments,
    required this.isOperator,
    required this.currentUserId,
    required this.onDelete,
  });

  final List<Profile> people;
  final List<Department> departments;
  final bool isOperator;
  final String? currentUserId;
  final ValueChanged<Profile> onDelete;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const PanelNotice('No one else yet.');
    return PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < people.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _row(context, people[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Profile person) {
    final tokens = context.nocturne;
    final department = departments
        .where((d) => d.id == person.departmentId)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          AvatarWell(
            initial: person.displayName.isEmpty
                ? '?'
                : person.displayName[0].toUpperCase(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.displayName),
                Text(
                  '@${person.username}',
                  style: TextStyle(fontSize: 13, color: tokens.neutral500),
                ),
              ],
            ),
          ),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                RolePlate(isManager: person.isManager),
                if (department != null)
                  DepartmentPlate(
                    name: department.name,
                    isOperator: department.isOperator,
                    isIt: department.isIt,
                  ),
              ],
            ),
          ),
          if (_canDelete(person))
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => onDelete(person),
            )
          else
            // Keeps the plates in a column when there is no delete icon.
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  bool _canDelete(Profile person) {
    if (person.id == currentUserId) return false;
    if (person.username.toLowerCase() == 'dev') return false;
    final department = departments
        .where((d) => d.id == person.departmentId)
        .firstOrNull;
    // Only an Operator can remove someone from the Operator/IT department —
    // same asymmetry as creating an account there.
    if (department?.isAdminTier ?? false) return isOperator;
    return true;
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

    return PanelCard(
      title: 'Developer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 14),
          const StampLabel('Accounts by department'),
          const SizedBox(height: 6),
          _Readout(
            child: departments.isEmpty
                ? Text('None.', style: TextStyle(color: tokens.neutral500))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final department in departments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${department.name}: '
                            '${people.where((p) => p.departmentId == department.id).length}',
                            style: _readoutStyle(tokens).copyWith(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          const StampLabel('Recent sync errors'),
          const SizedBox(height: 6),
          _Readout(
            child: syncLog.entries.isEmpty
                ? Text('None.', style: TextStyle(color: tokens.neutral500))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in syncLog.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${entry.at.toLocal()} · ${entry.source}/${entry.action} · '
                            '${entry.message}',
                            style: _readoutStyle(tokens).copyWith(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Tabular figures so digits line up like a seven-segment readout.
TextStyle _readoutStyle(NocturneColors tokens) => TextStyle(
  fontSize: 14,
  color: tokens.neutral200,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A recessed window the service-panel values are read through.
class _Readout extends StatelessWidget {
  const _Readout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: panelDecoration(context, depth: PanelDepth.recessed),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: child,
        ),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: StampLabel(label, size: 12),
            ),
          ),
          Expanded(
            child: _Readout(
              child: SelectableText(value, style: _readoutStyle(tokens)),
            ),
          ),
        ],
      ),
    );
  }
}
