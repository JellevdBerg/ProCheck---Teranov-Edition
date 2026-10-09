import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/task.dart';
import '../models/task_priority.dart';
import '../models/profile.dart';
import '../providers/auth_provider.dart';
import '../providers/department_members_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import 'attachments_editor.dart';
import 'due_date_calendar_dialog.dart';
import 'nocturne/nocturne_widgets.dart';
import 'notes_field.dart';
import 'panel/panel.dart';
import 'wobble_checkbox.dart';

/// A single task row: a checkbox + title that expands in place to reveal
/// its subtasks below and a notes panel beside them. Checking every
/// subtask automatically checks the task, and vice versa.
class TaskTile extends ConsumerStatefulWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onDelete,
    this.onExplicitDelete,
    this.autoRemoveWhenChecked = false,
    this.reorderIndex,
    this.expanded,
    this.onExpandedChanged,
  });

  final Task task;

  /// Called when the delete button is pressed (or, with
  /// [autoRemoveWhenChecked], once checking the task off finishes). The
  /// caller is responsible for actually removing the task — typically
  /// after a removal animation.
  final VoidCallback onDelete;

  /// Fired only when the user presses the trash icon directly — never for
  /// an [autoRemoveWhenChecked] removal. Lets a caller offer an "undo"
  /// affordance for a deliberate delete without also popping it up every
  /// time a quick task gets checked off and auto-removes itself.
  final VoidCallback? onExplicitDelete;

  /// Standalone (no-project) tasks are meant to be quick one-offs: once
  /// checked off, they remove themselves — but only after the check-off
  /// bounce has had time to play, never instantly.
  final bool autoRemoveWhenChecked;

  /// This tile's position within an enclosing `ReorderableListView`. When
  /// set, a drag handle is shown so the task can be dragged to reorder it;
  /// when null (the tile isn't inside a reorderable list), no handle is
  /// shown.
  final int? reorderIndex;

  /// When set (together with [onExpandedChanged]), this tile's expanded
  /// state is controlled by the caller instead of managed internally —
  /// used by [ProjectDetailOverlay] so opening one task collapses any
  /// other that's open (an accordion). Omit both to let the tile track
  /// its own expanded state, as it always has.
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  ConsumerState<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<TaskTile> {
  // Below this width there isn't room for subtasks and notes side by side,
  // so the notes panel stacks underneath instead.
  static const _sideBySideBreakpoint = 480.0;

  bool _expanded = false;
  Timer? _autoRemoveTimer;

  bool get _effectiveExpanded => widget.expanded ?? _expanded;

  void _setExpanded(bool value) {
    if (widget.onExpandedChanged != null) {
      widget.onExpandedChanged!(value);
    } else {
      setState(() => _expanded = value);
    }
  }

  // Snapshotting the checked flag as a primitive rather than comparing
  // oldWidget.task.isChecked to widget.task.isChecked directly: Task is a
  // mutable Hive object fetched by reference, so toggling it mutates the
  // exact same instance already held by the currently-mounted widget. By
  // the time didUpdateWidget runs, oldWidget.task and widget.task are the
  // identical, already-mutated object — comparing a field on them can never
  // see a "before" value. A bool, being a value type, is copied at the
  // point it's read and stays put regardless of later mutation — but it
  // must be captured eagerly in initState, not via a `late` initializer,
  // since a `late` field would defer that same first read until it's used
  // inside didUpdateWidget, by which point the mutation has already landed.
  bool _lastIsChecked = false;

  @override
  void initState() {
    super.initState();
    _lastIsChecked = widget.task.isChecked;
  }

  @override
  void didUpdateWidget(covariant TaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    final wasChecked = _lastIsChecked;
    final isChecked = widget.task.isChecked;
    _lastIsChecked = isChecked;

    if (!widget.autoRemoveWhenChecked) return;
    if (isChecked && !wasChecked) {
      // Let the check-off bounce actually play before this tile is
      // removed out from under it — an instant removal would tear the
      // checkbox down mid-animation and the bounce would never be seen.
      final reduceMotion = ref.read(settingsProvider).reduceMotion;
      if (reduceMotion) {
        widget.onDelete();
      } else {
        _autoRemoveTimer?.cancel();
        _autoRemoveTimer = Timer(WobbleCheckbox.duration, widget.onDelete);
      }
    } else if (!isChecked && wasChecked) {
      _autoRemoveTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _autoRemoveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final notifier = ref.read(tasksProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final reduceMotion = settings.reduceMotion;

    // Once expanded, the notes panel already shows the full text, so the
    // collapsed preview line would just be a duplicate. Due date shows as
    // its own tag (below) rather than duplicated into this text line.
    final subtitleParts = <String>[
      if (!_effectiveExpanded && (task.notes ?? '').trim().isNotEmpty)
        task.notes!.trim(),
      if (task.hasSubtasks)
        '${task.completedSubtaskCount}/${task.subtasks.length} subtasks',
    ];
    final priorityTag = NocturneTag.forPriority(task.priority);

    return Column(
      children: [
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NocturneRadius.md),
          ),
          hoverColor: context.nocturneHoverColor,
          splashColor: context.nocturneSplashColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          onTap: () => _setExpanded(!_effectiveExpanded),
          leading: WobbleCheckbox(
            value: task.isChecked,
            reduceMotion: reduceMotion,
            onChanged: (_) => notifier.toggleTask(task.id),
          ),
          title: Text(
            task.title,
            style: task.isChecked
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
          subtitle: subtitleParts.isEmpty
              ? null
              : Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ignore: use_null_aware_elements (hive_generator pins analyzer <7, which can't parse `?element`)
              if (priorityTag != null) priorityTag,
              if (task.priority != TaskPriority.none) const SizedBox(width: 6),
              if (task.dueDate != null) ...[
                NocturneTag(
                  label: formatDueLabel(task, settings.dateFormat),
                  icon: Icons.access_time,
                  outline: true,
                  // Neutral, not the Appearance accent — matches the rest of
                  // the row's text/icons, same overdue-red rule as the
                  // detail view's own due-date field (_DueDateRow below).
                  color:
                      task.dueDate!.isBefore(DateTime.now()) && !task.isChecked
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).hintColor,
                ),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete task',
                onPressed: () {
                  widget.onExplicitDelete?.call();
                  widget.onDelete();
                },
              ),
              Icon(_effectiveExpanded ? Icons.expand_less : Icons.expand_more),
              if (widget.reorderIndex != null)
                ReorderableDragStartListener(
                  index: widget.reorderIndex!,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.drag_indicator,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _effectiveExpanded
              ? TaskDetailEditor(task: task, breakpoint: _sideBySideBreakpoint)
              : const SizedBox(width: double.infinity),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

// A due date/time carries no separate "has a time" flag — setting a time
// is optional, and skipping it is marked by parking the time component at
// 23:59 (read as "due sometime that day" rather than a specific moment).
// The same sentinel marks a date range's end, which was always a
// whole-day concept. formatDueDate and _DueDateRow._pickDueDate are the
// two places that create or read it.
const _noTimeHour = 23;
const _noTimeMinute = 59;
bool _hasExplicitTime(DateTime d) =>
    !(d.hour == _noTimeHour && d.minute == _noTimeMinute);

/// Renders a due date's numeric date portion according to
/// [AppSettings.dateFormat] (e.g. "09/20/2026, 2:30 PM"), so it actually
/// matches whichever of the three formats is picked in Settings > Task
/// defaults rather than always showing the same fixed "Sep 20" style. Omits
/// the time portion entirely when no specific time was set.
String formatDueDate(DateTime dueDate, DateFormatOption format) {
  final datePart = _formatDateOnly(dueDate, format);
  if (!_hasExplicitTime(dueDate)) return datePart;

  final hour12 = dueDate.hour % 12 == 0 ? 12 : dueDate.hour % 12;
  final minute = dueDate.minute.toString().padLeft(2, '0');
  final period = dueDate.hour < 12 ? 'AM' : 'PM';
  return '$datePart, $hour12:$minute $period';
}

String _formatDateOnly(DateTime date, DateFormatOption format) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return switch (format) {
    DateFormatOption.mdy => '$month/$day/$year',
    DateFormatOption.dmy => '$day/$month/$year',
    DateFormatOption.iso => '$year-$month-$day',
  };
}

/// Renders a task's due date for display: a single moment (date + time) as
/// before, or, when [Task.dueDateEnd] is set, a "start - end" date range
/// (dates only, since a range spans whole days rather than a single
/// moment).
String formatDueLabel(Task task, DateFormatOption format) {
  final dueDate = task.dueDate;
  if (dueDate == null) return '';
  final dueDateEnd = task.dueDateEnd;
  if (dueDateEnd == null) return formatDueDate(dueDate, format);
  return '${_formatDateOnly(dueDate, format)} - ${_formatDateOnly(dueDateEnd, format)}';
}

/// The due date/priority/subtasks/notes/attachments editing region shared
/// by [TaskTile]'s expanded row and the task-creation sheet: subtasks below,
/// with a notes panel that sits to the right when there's room for it and
/// stacks underneath otherwise.
class ExpandedTaskDetail extends ConsumerWidget {
  const ExpandedTaskDetail({
    super.key,
    required this.task,
    required this.notesController,
    required this.notesFocusNode,
    required this.newSubtaskController,
    required this.onAddSubtask,
    required this.breakpoint,
    this.padding = const EdgeInsets.fromLTRB(56, 0, 16, 16),
  });

  final Task task;
  final TextEditingController notesController;
  final FocusNode notesFocusNode;
  final TextEditingController newSubtaskController;
  final VoidCallback onAddSubtask;
  final double breakpoint;

  /// Defaults to [TaskTile]'s own indent (aligning under its checkbox +
  /// title); a caller without that leading row, like the task-creation
  /// sheet, passes its own.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final subtasks = _SubtasksSection(
            task: task,
            newSubtaskController: newSubtaskController,
            onAddSubtask: onAddSubtask,
          );
          final notes = NotesField(
            controller: notesController,
            focusNode: notesFocusNode,
          );
          final notesAndAttachments = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              notes,
              const SizedBox(height: 16),
              AttachmentsEditor(
                attachments: task.attachments,
                onAdd: (picked) => ref
                    .read(tasksProvider.notifier)
                    .addAttachments(task.id, picked),
                onRemoveAt: (index) => ref
                    .read(tasksProvider.notifier)
                    .removeAttachment(task.id, index),
              ),
            ],
          );

          final topRow = Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: _DueDateRow(task: task)),
                const SizedBox(width: 16),
                _PriorityRow(task: task),
              ],
            ),
          );
          final teamRow = isSupabaseConfigured
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AssigneeAndEstimateRow(task: task),
                )
              : const SizedBox.shrink();

          if (constraints.maxWidth >= breakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                topRow,
                teamRow,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: subtasks),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: notesAndAttachments),
                  ],
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              topRow,
              teamRow,
              notesAndAttachments,
              const SizedBox(height: 12),
              subtasks,
            ],
          );
        },
      ),
    );
  }
}

/// [ExpandedTaskDetail] plus the controllers/lifecycle it needs — the
/// reusable, self-contained version of the editing region [TaskTile] shows
/// once expanded. Anywhere else that needs the same due
/// date/priority/subtasks/notes/attachments editing for a task (the
/// task-creation sheet, notably) uses this directly instead of
/// re-implementing that wiring.
class TaskDetailEditor extends ConsumerStatefulWidget {
  const TaskDetailEditor({
    super.key,
    required this.task,
    this.breakpoint = 480,
    this.padding = const EdgeInsets.fromLTRB(56, 0, 16, 16),
  });

  final Task task;
  final double breakpoint;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<TaskDetailEditor> createState() => _TaskDetailEditorState();
}

class _TaskDetailEditorState extends ConsumerState<TaskDetailEditor> {
  late final TextEditingController _notesController;
  late final FocusNode _notesFocusNode;
  final _newSubtaskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.task.notes ?? '');
    _notesFocusNode = FocusNode()..addListener(_onNotesFocusChange);
  }

  @override
  void didUpdateWidget(covariant TaskDetailEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the field in sync with external changes (e.g. undo elsewhere)
    // without clobbering text the user is actively editing.
    if (!_notesFocusNode.hasFocus &&
        widget.task.notes != oldWidget.task.notes) {
      _notesController.text = widget.task.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notesFocusNode.removeListener(_onNotesFocusChange);
    _notesFocusNode.dispose();
    _notesController.dispose();
    _newSubtaskController.dispose();
    super.dispose();
  }

  void _onNotesFocusChange() {
    if (!_notesFocusNode.hasFocus) _saveNotes();
  }

  void _saveNotes() {
    final text = _notesController.text.trim();
    ref
        .read(tasksProvider.notifier)
        .setTaskNotes(widget.task.id, text.isEmpty ? null : text);
  }

  void _addSubtask() {
    final title = _newSubtaskController.text.trim();
    if (title.isEmpty) return;
    ref.read(tasksProvider.notifier).addSubtask(widget.task.id, title);
    _newSubtaskController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ExpandedTaskDetail(
      task: widget.task,
      notesController: _notesController,
      notesFocusNode: _notesFocusNode,
      newSubtaskController: _newSubtaskController,
      onAddSubtask: _addSubtask,
      breakpoint: widget.breakpoint,
      padding: widget.padding,
    );
  }
}

class _DueDateRow extends ConsumerWidget {
  const _DueDateRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dueDate = task.dueDate;
    final isOverdue =
        dueDate != null && !task.isChecked && dueDate.isBefore(DateTime.now());
    final dateFormat = ref.watch(settingsProvider).dateFormat;

    return Row(
      children: [
        Icon(
          Icons.alarm_outlined,
          size: 18,
          color: isOverdue ? theme.colorScheme.error : theme.hintColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: dueDate == null
              ? TextButton(
                  onPressed: () => _pickDueDate(context, ref),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    alignment: Alignment.centerLeft,
                  ),
                  child: const Text('Set due date'),
                )
              : DecoratedBox(
                  decoration: panelDecoration(
                    context,
                    depth: PanelDepth.recessed,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(NocturneRadius.md),
                      hoverColor: context.nocturneHoverColor,
                      splashColor: context.nocturneSplashColor,
                      highlightColor: context.nocturneSplashColor,
                      onTap: () => _pickDueDate(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'Due ${formatDueLabel(task, dateFormat)}',
                          style: TextStyle(
                            color: isOverdue ? theme.colorScheme.error : null,
                            fontWeight: isOverdue ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        if (dueDate != null)
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove due date',
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                ref.read(tasksProvider.notifier).setTaskDueDate(task.id, null),
          ),
      ],
    );
  }

  /// One calendar for both a single due date and a date range — see
  /// [showDueDateCalendarDialog]. Due dates are date-only now (no time
  /// step), so picking either just sets the date straight away; an
  /// existing explicit time (set before that functionality was removed)
  /// is preserved rather than silently dropped when its date is changed.
  Future<void> _pickDueDate(BuildContext context, WidgetRef ref) async {
    final selection = await showDueDateCalendarDialog(
      context,
      initialStart: task.dueDate,
      initialEnd: task.dueDateEnd,
    );
    if (selection == null || !context.mounted) return;

    final previousTime = task.dueDate;
    final keepsTime = previousTime != null && _hasExplicitTime(previousTime);
    final start = DateTime(
      selection.start.year,
      selection.start.month,
      selection.start.day,
      keepsTime ? previousTime.hour : _noTimeHour,
      keepsTime ? previousTime.minute : _noTimeMinute,
    );

    if (selection.end != null) {
      final end = DateTime(
        selection.end!.year,
        selection.end!.month,
        selection.end!.day,
        _noTimeHour,
        _noTimeMinute,
      );
      ref
          .read(tasksProvider.notifier)
          .setTaskDueDate(task.id, start, dueDateEnd: end);
      return;
    }

    ref.read(tasksProvider.notifier).setTaskDueDate(task.id, start);
  }
}

class _PriorityRow extends ConsumerWidget {
  const _PriorityRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NocturneSegmented<TaskPriority>(
      options: TaskPriority.values,
      value: task.priority,
      labelBuilder: (p) => p.label,
      onChanged: (p) =>
          ref.read(tasksProvider.notifier).setTaskPriority(task.id, p),
    );
  }
}

/// Shown only once Supabase is configured — who this task is assigned to,
/// and how long it's expected to take. Only a manager/Operator can actually
/// change the assignee (the `tasks_update` RLS policy enforces that
/// server-side; a member sees it read-only). The estimate is editable by
/// whoever can edit the task at all, same as notes/priority.
class _AssigneeAndEstimateRow extends ConsumerWidget {
  const _AssigneeAndEstimateRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final canAssign = profile?.isManager ?? false;
    final members =
        ref.watch(departmentMembersProvider).valueOrNull ?? const <Profile>[];

    return Row(
      children: [
        Icon(Icons.person_outline, size: 18, color: theme.hintColor),
        const SizedBox(width: 8),
        if (canAssign)
          DecoratedBox(
            decoration: panelDecoration(context),
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AssigneeBadge(name: _assigneeName(task.assigneeId, members)),
                  const SizedBox(width: 6),
                  DropdownButton<String?>(
                    value: task.assigneeId,
                    hint: const Text('Unassigned'),
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Unassigned'),
                      ),
                      for (final member in members)
                        DropdownMenuItem<String?>(
                          value: member.id,
                          child: Text(member.displayName),
                        ),
                    ],
                    onChanged: (assigneeId) => ref
                        .read(tasksProvider.notifier)
                        .assignTask(task.id, assigneeId),
                  ),
                ],
              ),
            ),
          )
        else
          DecoratedBox(
            decoration: panelDecoration(context, depth: PanelDepth.recessed),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AssigneeBadge(name: _assigneeName(task.assigneeId, members)),
                  const SizedBox(width: 6),
                  Text(
                    _assigneeLabel(task.assigneeId, members),
                    style: TextStyle(color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(width: 20),
        Icon(Icons.timer_outlined, size: 18, color: theme.hintColor),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: TextFormField(
            key: ValueKey('estimate-${task.id}-${task.estimatedMinutes}'),
            initialValue: task.estimatedMinutes?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(isDense: true, hintText: 'min'),
            onFieldSubmitted: (value) {
              final minutes = int.tryParse(value.trim());
              ref
                  .read(tasksProvider.notifier)
                  .setTaskEstimate(task.id, minutes);
            },
          ),
        ),
      ],
    );
  }

  String? _assigneeName(String? assigneeId, List<Profile> members) {
    for (final member in members) {
      if (member.id == assigneeId) return member.displayName;
    }
    return null;
  }

  String _assigneeLabel(String? assigneeId, List<Profile> members) {
    if (assigneeId == null) return 'Unassigned';
    for (final member in members) {
      if (member.id == assigneeId) return member.displayName;
    }
    return 'Unassigned';
  }
}

/// Initials in a recessed round well; empty (no initials) when unassigned.
class _AssigneeBadge extends StatelessWidget {
  const _AssigneeBadge({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? ''
        : parts.take(2).map((w) => w[0]).join().toUpperCase();
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: panelDecoration(
        context,
        depth: PanelDepth.recessed,
        radius: 12,
      ),
      child: initials.isEmpty
          ? null
          : Text(
              initials,
              style: TextStyle(
                fontFamily: kPanelFont,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.4,
                color: context.nocturne.text,
              ),
            ),
    );
  }
}

class _SubtasksSection extends ConsumerWidget {
  const _SubtasksSection({
    required this.task,
    required this.newSubtaskController,
    required this.onAddSubtask,
  });

  final Task task;
  final TextEditingController newSubtaskController;
  final VoidCallback onAddSubtask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(tasksProvider.notifier);
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (task.subtasks.isNotEmpty) ...[
          const StampLabel('Subtasks'),
          const SizedBox(height: 6),
          for (final subtask in task.subtasks)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              onTap: () => notifier.toggleSubtask(task.id, subtask.id),
              leading: WobbleCheckbox(
                value: subtask.isChecked,
                reduceMotion: reduceMotion,
                onChanged: (_) => notifier.toggleSubtask(task.id, subtask.id),
              ),
              title: Text(
                subtask.title,
                style: subtask.isChecked
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove subtask',
                onPressed: () => notifier.removeSubtask(task.id, subtask.id),
              ),
            ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: newSubtaskController,
                decoration: const InputDecoration(
                  hintText: 'Add a subtask',
                  isDense: true,
                ),
                onSubmitted: (_) => onAddSubtask(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.add), onPressed: onAddSubtask),
          ],
        ),
      ],
    );
  }
}
