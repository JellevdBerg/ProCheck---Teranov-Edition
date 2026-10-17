import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/task.dart';
import '../models/task_priority.dart';
import '../models/profile.dart';
import '../providers/auth_provider.dart';
import '../providers/department_members_provider.dart';
import '../providers/roles_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import 'attachments_editor.dart';
import 'due_date_calendar_dialog.dart';
import 'nocturne/nocturne_widgets.dart';
import 'notes_field.dart';
import 'panel/panel.dart';
import 'people_plates.dart';
import 'sync_status_indicator.dart';
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
    final compact = settings.compactRows;

    // Once expanded, the notes panel already shows the full text, so the
    // collapsed preview line would just be a duplicate.
    final notesPreview =
        !_effectiveExpanded && (task.notes ?? '').trim().isNotEmpty
        ? task.notes!.trim()
        : null;
    final tokens = context.nocturne;

    return Column(
      children: [
        TaskRowFocus(
          onToggle: () => notifier.toggleTask(task.id),
          child: ListTile(
            dense: true,
            visualDensity: compact
                ? const VisualDensity(horizontal: -2, vertical: -2)
                : VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NocturneRadius.md),
            ),
            hoverColor: context.nocturneHoverColor,
            splashColor: context.nocturneSplashColor,
            contentPadding: const EdgeInsets.only(
              left: NocturneSpace.s3,
              right: NocturneSpace.s1,
            ),
            minVerticalPadding: compact ? NocturneSpace.s1 / 2 : NocturneSpace.s1,
            horizontalTitleGap: NocturneSpace.s2,
            minLeadingWidth: 28,
            onTap: () => _setExpanded(!_effectiveExpanded),
            leading: WobbleCheckbox(
              value: task.isChecked,
              reduceMotion: reduceMotion,
              onChanged: (_) => notifier.toggleTask(task.id),
            ),
            title: LayoutBuilder(
              builder: (context, constraints) {
                final title = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        task.title,
                        style: TextStyle(
                          color: task.isChecked ? tokens.neutral500 : tokens.text,
                          decoration: task.isChecked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    PendingSyncMark(table: 'tasks', rowId: task.id),
                  ],
                );
                final hasMeta =
                    task.dueDate != null ||
                    task.priority != TaskPriority.none ||
                    task.hasSubtasks ||
                    task.assigneeId != null;
                // Inline and right-aligned when there is room, otherwise the
                // meta wraps onto its own line under the title.
                if (constraints.maxWidth >= 480) {
                  return Row(
                    children: [
                      Expanded(child: title),
                      if (hasMeta) ...[
                        const SizedBox(width: NocturneSpace.s2),
                        // Not a Flexible: that would split the free space 50/50 with the
                        // title and leave the meta floating mid-row.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.6,
                          ),
                          child: TaskMeta(task: task),
                        ),
                      ],
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (hasMeta) ...[
                      const SizedBox(height: NocturneSpace.s1),
                      TaskMeta(task: task),
                    ],
                  ],
                );
              },
            ),
            subtitle: notesPreview == null
                ? null
                : Text(
                    notesPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete task',
                  visualDensity: compact
                      ? const VisualDensity(horizontal: -2, vertical: -2)
                      : VisualDensity.compact,
                  onPressed: () {
                    widget.onExplicitDelete?.call();
                    widget.onDelete();
                  },
                ),
                Icon(
                  _effectiveExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                if (widget.reorderIndex != null)
                  ReorderableDragStartListener(
                    index: widget.reorderIndex!,
                    child: Padding(
                      padding: const EdgeInsets.only(left: NocturneSpace.s1),
                      child: Icon(
                        Icons.drag_indicator,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ),
              ],
            ),
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

/// Keyboard check-off for a task row: Up/Down move a 2px accent outline
/// between sibling rows, Space runs [onToggle] (the checkbox's own handler).
/// Only acts while this row itself holds primary focus, so typing in a text
/// field (even one nested in an expanded row) is never intercepted.
class TaskRowFocus extends StatefulWidget {
  const TaskRowFocus({super.key, required this.child, required this.onToggle});

  final Widget child;
  final VoidCallback onToggle;

  @override
  State<TaskRowFocus> createState() => _TaskRowFocusState();
}

class _TaskRowFocusState extends State<TaskRowFocus> {
  static const _label = 'task-row';
  final _node = FocusNode(debugLabel: _label);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) widget.onToggle();
      return KeyEventResult.handled;
    }
    final step = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    if (step == 0) return KeyEventResult.ignored;
    final rows = FocusScope.of(context).traversalDescendants
        .where((n) => n.debugLabel == _label && n.canRequestFocus)
        .toList();
    final i = rows.indexOf(node) + step;
    if (i >= 0 && i < rows.length) rows[i].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      onFocusChange: (_) => setState(() {}),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NocturneRadius.sm),
          border: _node.hasPrimaryFocus
              ? Border.all(color: context.nocturneAccent, width: 2)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Red when overdue, amber when due within 48h, otherwise null (neutral).
/// Checked tasks never show urgency.
Color? dueTone(Task task, NocturneColors tokens) {
  final due = task.dueDate;
  if (due == null || task.isChecked) return null;
  final now = DateTime.now();
  if (due.isBefore(now)) return tokens.danger;
  if (due.difference(now) < const Duration(hours: 48)) return tokens.warn;
  return null;
}

/// The compact meta cluster shared by task rows: priority tag, due chip,
/// subtask count and (once Supabase is configured) the assignee avatar.
class TaskMeta extends ConsumerWidget {
  const TaskMeta({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;
    final dateFormat = ref.watch(settingsProvider).dateFormat;
    final priorityTag = NocturneTag.forPriority(task.priority);
    final tone = dueTone(task, tokens);
    return Wrap(
      spacing: NocturneSpace.s2,
      runSpacing: NocturneSpace.s1,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        // ignore: use_null_aware_elements (hive_generator pins analyzer <7, which can't parse `?element`)
        if (priorityTag != null) priorityTag,
        if (task.dueDate != null)
          NocturneTag(
            label: formatDueLabel(task, dateFormat),
            icon: Icons.access_time,
            color: tone,
            outline: tone == null,
          ),
        if (task.hasSubtasks)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.checklist, size: 14, color: tokens.neutral500),
              const SizedBox(width: NocturneSpace.s1),
              Text(
                '${task.completedSubtaskCount}/${task.subtasks.length} subtasks',
                style: TextStyle(fontSize: 12, color: tokens.neutral400),
              ),
            ],
          ),
        if (isSupabaseConfigured && task.assigneeId != null)
          _RowAssignee(assigneeId: task.assigneeId!),
      ],
    );
  }
}

class _RowAssignee extends ConsumerWidget {
  const _RowAssignee({required this.assigneeId});

  final String assigneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        ref.watch(departmentMembersProvider).valueOrNull ?? const <Profile>[];
    final directory =
        ref.watch(profileDirectoryProvider).valueOrNull ??
        const <String, DirectoryEntry>{};
    final name = _assigneeName(assigneeId, members, directory);
    return Tooltip(
      message: name ?? 'Unassigned',
      child: AvatarWell(
        initial: initialsFor(name),
        size: 20,
        dashed: name == null,
      ),
    );
  }
}

String? _assigneeName(
  String? assigneeId,
  List<Profile> members,
  Map<String, DirectoryEntry> directory,
) {
  for (final member in members) {
    if (member.id == assigneeId) return member.displayName;
  }
  return directory[assigneeId]?.displayName;
}

/// Up to two initials for an avatar; empty for a missing name.
String initialsFor(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return parts.isEmpty
      ? ''
      : parts.take(2).map((w) => w[0]).join().toUpperCase();
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
            child: Wrap(
              spacing: NocturneSpace.s4,
              runSpacing: NocturneSpace.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DueDateRow(task: task),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.alarm_outlined,
          size: 18,
          color: isOverdue ? context.nocturne.danger : theme.hintColor,
        ),
        const SizedBox(width: 8),
        Flexible(
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
                            color: isOverdue ? context.nocturne.danger : null,
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
    // Managers and roles with "add and assign tasks" (the database decides).
    final canAssign = profile != null && ref.watch(permissionsProvider).manageTasks;
    final members =
        ref.watch(departmentMembersProvider).valueOrNull ?? const <Profile>[];
    // A member can't read other profiles directly, so name an assignee who
    // isn't in [members] through the directory.
    final directory =
        ref.watch(profileDirectoryProvider).valueOrNull ??
        const <String, DirectoryEntry>{};

    final assignee = _assigneeName(task.assigneeId, members, directory);
    final myId = profile?.id;
    final ownerName = task.ownerId.isEmpty
        ? null
        : task.ownerId == myId
        ? 'You'
        : directory[task.ownerId]?.displayName;
    // Everyone in the task's department, by name (the directory works for
    // roles that can assign tasks but cannot read other profiles directly).
    // Deactivated people (Phase 4 lifecycle) drop out of the pickable
    // options — the putIfAbsent below still shows a name if the task is
    // already assigned to one, so history keeps reading correctly.
    final byId = <String, String>{
      for (final m in members)
        if (m.isActive) m.id: m.displayName,
      for (final e in directory.values)
        if (e.departmentId == task.departmentId && e.isActive) e.id: e.displayName,
    };
    if (task.assigneeId != null && assignee != null) {
      byId.putIfAbsent(task.assigneeId!, () => assignee);
    }
    final assigneeOptions = byId.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final avatar = AvatarWell(
      initial: initialsFor(assignee),
      size: 24,
      dashed: assignee == null,
    );

    return Wrap(
      spacing: NocturneSpace.s4,
      runSpacing: NocturneSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 18, color: theme.hintColor),
            const SizedBox(width: NocturneSpace.s2),
            if (canAssign)
              DecoratedBox(
                decoration: panelDecoration(
                  context,
                  depth: PanelDepth.recessed,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      avatar,
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
                          for (final option in assigneeOptions)
                            DropdownMenuItem<String?>(
                              value: option.key,
                              child: Text(option.value),
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
                decoration: panelDecoration(
                  context,
                  depth: PanelDepth.recessed,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      avatar,
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          task.assigneeId != null && task.assigneeId == myId
                              ? 'You'
                              : _assigneeLabel(
                                  task.assigneeId,
                                  members,
                                  directory,
                                ),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.hintColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (ownerName != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Owner', style: TextStyle(color: theme.hintColor)),
              const SizedBox(width: NocturneSpace.s2),
              AvatarWell(
                initial: initialsFor(ownerName == 'You' ? null : ownerName),
                size: 24,
              ),
              const SizedBox(width: 6),
              Text(ownerName),
            ],
          ),
        if (task.isChecked && task.completedAt != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: context.nocturne.done),
              const SizedBox(width: NocturneSpace.s2),
              Text(
                'Checked off${task.completedBy == null ? '' : ' by ${task.completedBy == myId ? 'You' : (directory[task.completedBy]?.displayName ?? 'a teammate')}'}'
                ' · ${_stamp(task.completedAt!.toLocal())}',
                style: TextStyle(color: theme.hintColor),
              ),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 18, color: theme.hintColor),
            const SizedBox(width: NocturneSpace.s2),
            SizedBox(
              width: 72,
              child: TextFormField(
                key: ValueKey('estimate-${task.id}-${task.estimatedMinutes}'),
                initialValue: task.estimatedMinutes?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'min',
                ),
                onFieldSubmitted: (value) {
                  final minutes = int.tryParse(value.trim());
                  ref
                      .read(tasksProvider.notifier)
                      .setTaskEstimate(task.id, minutes);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _assigneeLabel(
    String? assigneeId,
    List<Profile> members,
    Map<String, DirectoryEntry> directory,
  ) {
    if (assigneeId == null) return 'Unassigned';
    for (final member in members) {
      if (member.id == assigneeId) return member.displayName;
    }
    return directory[assigneeId]?.displayName ?? 'Unassigned';
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

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
