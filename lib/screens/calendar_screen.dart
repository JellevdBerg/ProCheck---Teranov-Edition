import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../models/task_priority.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/create_task_sheet.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';

/// How long the Taskmaster drag-preview ghost's `AnimatedPositioned` takes
/// to tween to a new position/width — shared with `_CalendarCrossingPillState`
/// so its post-weekend-exit linger window (see `_weekendLingerUntil`) stays
/// in sync with how long the box actually takes to catch up.
const _dragGhostAnimationDuration = Duration(milliseconds: 150);

// A Month-view day row's fixed pixel geometry, shared by the lane-count-
// that-fits math ([_maxLanesForHeight]) and the Taskmaster drag-ghost's
// positioning (which lane it visually lands in) — one source of truth so
// the two can never drift apart.
const _rowTopInset = 35.0; // 6px top padding + the day-number row + 3px gap
const _laneHeight = 30.0; // 27px bar + 3px gap below it
const _overflowChipHeight = 20.0;

/// Corner radius of a task bar (and of its weekend connector's cap).
const _barRadius = 6.0;

/// Below this column width a day cell can't hold readable bars, so the grid
/// switches to compact cells: day number, a few dots and a "+N" count. Tapping
/// a compact cell does what tapping its day number does.
const _compactCellWidth = 84.0;
const _rowBottomPadding = 6.0;

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _weekdayLabels = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Steps a calendar date by [days] (negative to go backward) — rebuilding
/// the date from its year/month/day fields rather than adding a `Duration`,
/// which is calendar-correct across a daylight-saving transition. A plain
/// `date.add(Duration(days: n))` only adds exactly 24*n hours, so stepping
/// across the October DST fall-back (a 25-hour day) lands an hour short of
/// midnight on the intended day and reads as the day before it instead.
DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

DateTime _weekStartOf(DateTime d) => _addDays(d, -(d.weekday - 1));

/// Splits a row-relative column span (0=Monday..6=Sunday, inclusive) into
/// its weekday-column count and weekend-column count. Handles every case
/// uniformly — including a span that starts *within* the weekend itself
/// (e.g. a task or drag beginning directly on a Saturday, with no weekday
/// portion at all) — rather than only the common case of a weekday run
/// that extends into the weekend, which a plain `colStart <= 4` guard can
/// misclassify as a weekday-only span and render at the wrong height.
({int weekdayCols, int weekendCols}) _weekendSplit(int colStart, int colEnd) {
  final int weekdayEnd = math.min(colEnd, 4);
  final int weekdayCols = colStart <= 4 ? weekdayEnd - colStart + 1 : 0;
  final int weekendStart = math.max(colStart, 5);
  final int weekendCols = colEnd >= 5 ? colEnd - weekendStart + 1 : 0;
  return (weekdayCols: weekdayCols, weekendCols: weekendCols);
}

enum _CalendarView { week, month }

/// A full calendar — Month for an overview of everything on the books,
/// Week to hyperfocus on the next 7 days. Every task with a due date shows
/// as a bar on its day(s): a multi-day task draws one continuous bar across
/// its span (rounded caps only at its true start/end), and tasks landing on
/// the same days stack into their own lanes rather than overlapping. The
/// grid always fills the screen's full height, even on a quiet week.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({
    super.key,
    required this.onDaySelected,
    required this.onOpenTask,
  });

  final ValueChanged<DateTime> onDaySelected;

  /// Opens a task's home — its project, scrolled to and highlighting that
  /// task (same destination as tapping it from the Dashboard's attention
  /// list), or the Projects screen's unfiled list when it has no project.
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _anchor = _dateOnly(DateTime.now());
  _CalendarView _view = _CalendarView.month;

  bool _taskmasterOn = false;
  DateTime? _dragAnchor;
  DateTime? _dragCursor;
  Timer? _edgeAdvanceTimer;
  DateTime? _edgeAdvanceTarget;

  @override
  void dispose() {
    _edgeAdvanceTimer?.cancel();
    super.dispose();
  }

  void _step(int delta) {
    setState(() {
      _anchor = _view == _CalendarView.month
          ? DateTime(_anchor.year, _anchor.month + delta, 1)
          : _addDays(_anchor, 7 * delta);
    });
  }

  void _goToToday() => setState(() => _anchor = _dateOnly(DateTime.now()));

  void _handleDragStart(DateTime day) {
    setState(() {
      _dragAnchor = day;
      _dragCursor = day;
    });
  }

  /// Tracks the drag cursor, and — only in Month view, only once the pointer
  /// has settled on a dimmed leading/trailing day for a moment — auto-steps
  /// the month so a drag can extend a task across a month boundary without
  /// the user having to let go and start over.
  void _handleDragUpdate(DateTime hovered) {
    setState(() => _dragCursor = hovered);
    if (_view != _CalendarView.month) return;

    final firstOfMonth = DateTime(_anchor.year, _anchor.month, 1);
    final isNext = hovered.isAfter(
      DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0),
    );
    final isPrev = hovered.isBefore(firstOfMonth);

    if (!isNext && !isPrev) {
      _edgeAdvanceTimer?.cancel();
      _edgeAdvanceTarget = null;
      return;
    }
    if (_edgeAdvanceTarget != null &&
        _isSameDay(_edgeAdvanceTarget!, hovered)) {
      return;
    }
    _edgeAdvanceTimer?.cancel();
    _edgeAdvanceTarget = hovered;
    _edgeAdvanceTimer = Timer(const Duration(milliseconds: 650), () {
      setState(() {
        _anchor = DateTime(_anchor.year, _anchor.month + (isNext ? 1 : -1), 1);
        _dragCursor = hovered;
      });
    });
  }

  Future<void> _handleDragEnd() async {
    _edgeAdvanceTimer?.cancel();
    _edgeAdvanceTarget = null;
    final anchor = _dragAnchor;
    final cursor = _dragCursor;
    setState(() {
      _dragAnchor = null;
      _dragCursor = null;
    });
    if (anchor == null || cursor == null) return;
    final start = anchor.isBefore(cursor) ? anchor : cursor;
    final end = anchor.isBefore(cursor) ? cursor : anchor;
    await _createTaskForRange(start, end);
  }

  void _cancelDrag() {
    _edgeAdvanceTimer?.cancel();
    _edgeAdvanceTarget = null;
    setState(() {
      _dragAnchor = null;
      _dragCursor = null;
    });
  }

  /// Opens the new-task sheet pre-filled with the range just drawn on the
  /// calendar, so its due date section already shows that date (still
  /// editable there) instead of created task briefly reading "Set due date".
  Future<void> _createTaskForRange(DateTime start, DateTime end) async {
    await showCreateTaskSheet(
      context,
      initialDueDate: start,
      initialDueDateEnd: _isSameDay(start, end) ? null : end,
    );
  }

  /// A task filed under a project opens that project, scrolled to it; an
  /// unfiled task opens the Projects screen's unfiled list instead — the
  /// same standard "open this task" behavior used everywhere else in the
  /// app.
  void _handleTaskTap(Task task, BuildContext rowContext) {
    widget.onOpenTask(task.projectId, task.id, rowContext);
  }

  String get _headerLabel {
    if (_view == _CalendarView.month) {
      return '${_monthNames[_anchor.month - 1]} ${_anchor.year}';
    }
    final start = _weekStartOf(_anchor);
    final end = _addDays(start, 6);
    final startLabel =
        '${_monthNames[start.month - 1].substring(0, 3)} ${start.day}';
    final endLabel = start.month == end.month
        ? '${end.day}'
        : '${_monthNames[end.month - 1].substring(0, 3)} ${end.day}';
    return '$startLabel – $endLabel, ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final projects = ref.watch(projectsProvider);
    final projectsById = {for (final p in projects) p.id: p};
    final today = DateTime.now();

    final firstOfMonth = DateTime(_anchor.year, _anchor.month, 1);
    final gridStart = _addDays(firstOfMonth, -(firstOfMonth.weekday - 1));

    // Scanning the full, unscoped task list happens once here instead of
    // once per _WeekRow (6x in month view) — each row's own _computeLanes
    // then only scans this already-narrow, visible-window subset.
    final visibleRangeStart = _view == _CalendarView.month
        ? gridStart
        : _weekStartOf(_anchor);
    final visibleRangeEnd = _addDays(
      visibleRangeStart,
      _view == _CalendarView.month ? 41 : 6,
    );
    final visibleTasks = _tasksOverlappingRange(
      tasks,
      visibleRangeStart,
      visibleRangeEnd,
    );

    final dragRange = (_dragAnchor != null && _dragCursor != null)
        ? (
            _dragAnchor!.isBefore(_dragCursor!) ? _dragAnchor! : _dragCursor!,
            _dragAnchor!.isBefore(_dragCursor!) ? _dragCursor! : _dragAnchor!,
          )
        : null;
    void onTaskDelete(Task task) =>
        ref.read(tasksProvider.notifier).deleteTask(task.id);

    return LayoutBuilder(
      builder: (context, outer) {
        final compact = outer.maxWidth < NocturneBreakpoints.compact;
        final pad = compact ? NocturneSpace.s4 : NocturneSpace.s6;
        // Roughly one grid column (the grid is inset by the page padding).
        final colWidth = (outer.maxWidth - 2 * pad) / 7;

        final todayButton = NocturneButton(
          label: 'Today',
          icon: Icons.today_outlined,
          variant: NocturneButtonVariant.primary,
          dense: true,
          onPressed: _goToToday,
        );
        final chevrons = [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            visualDensity: VisualDensity.compact,
            onPressed: () => _step(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            visualDensity: VisualDensity.compact,
            onPressed: () => _step(1),
          ),
        ];
        final headerText = Text(
          _headerLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: compact
              ? Theme.of(context).textTheme.titleMedium
              : Theme.of(context).textTheme.headlineSmall,
        );
        final taskmaster = Tooltip(
          message: _taskmasterOn
              ? 'Click or drag a day to add a task there'
              : 'Turn on to click or drag on the calendar to add tasks',
          child: NocturneButton(
            label: 'Taskmaster',
            icon: Icons.touch_app_outlined,
            dense: true,
            variant: _taskmasterOn
                ? NocturneButtonVariant.primary
                : NocturneButtonVariant.secondary,
            onPressed: () {
              _cancelDrag();
              setState(() => _taskmasterOn = !_taskmasterOn);
            },
          ),
        );
        final viewToggle = NocturneSegmented<_CalendarView>(
          options: _CalendarView.values,
          value: _view,
          labelBuilder: (v) => v == _CalendarView.week ? 'Week' : 'Month',
          onChanged: (v) => setState(() => _view = v),
        );

        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                // Two short rows instead of one that can't fit.
                Row(
                  children: [
                    todayButton,
                    const SizedBox(width: NocturneSpace.s2),
                    ...chevrons,
                    const SizedBox(width: NocturneSpace.s1),
                    Flexible(child: headerText),
                  ],
                ),
                const SizedBox(height: NocturneSpace.s2),
                Row(
                  children: [
                    taskmaster,
                    const SizedBox(width: NocturneSpace.s2),
                    Flexible(child: viewToggle),
                  ],
                ),
              ] else
                Row(
                  children: [
                    todayButton,
                    const SizedBox(width: NocturneSpace.s2),
                    ...chevrons,
                    const SizedBox(width: NocturneSpace.s1),
                    Flexible(child: headerText),
                    const Spacer(),
                    taskmaster,
                    const SizedBox(width: NocturneSpace.s2),
                    viewToggle,
                  ],
                ),
              const SizedBox(height: NocturneSpace.s3),
              Row(
                children: [
                  for (final label in _weekdayLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          colWidth >= 110 ? label : label.substring(0, 3),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            height: 16 / 11,
                            fontWeight: FontWeight.w600,
                            color: context.nocturne.neutral500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: NocturneSpace.s1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final gridSize = constraints.biggest;
                    final rowsCount = _view == _CalendarView.month ? 6 : 1;
                    final weekStart = _view == _CalendarView.month
                        ? gridStart
                        : _weekStartOf(_anchor);

                    DateTime dateAt(Offset local) {
                      final col = (local.dx / gridSize.width * 7).floor().clamp(
                        0,
                        6,
                      );
                      final row = (local.dy / gridSize.height * rowsCount)
                          .floor()
                          .clamp(0, rowsCount - 1);
                      return _addDays(weekStart, row * 7 + col);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: _taskmasterOn
                          ? (d) => _handleDragStart(dateAt(d.localPosition))
                          : null,
                      onPanUpdate: _taskmasterOn
                          ? (d) => _handleDragUpdate(dateAt(d.localPosition))
                          : null,
                      onPanEnd: _taskmasterOn ? (_) => _handleDragEnd() : null,
                      onPanCancel: _taskmasterOn ? _cancelDrag : null,
                      child: Container(
                        decoration: panelDecoration(context),
                        clipBehavior: Clip.antiAlias,
                        child: _view == _CalendarView.month
                            ? Column(
                                children: [
                                  for (var week = 0; week < 6; week++)
                                    Expanded(
                                      child: _WeekRow(
                                        rowStart: _addDays(gridStart, week * 7),
                                        month: _anchor,
                                        today: today,
                                        tasks: visibleTasks,
                                        projectsById: projectsById,
                                        onDayTap: _taskmasterOn
                                            ? (day) =>
                                                  _createTaskForRange(day, day)
                                            : widget.onDaySelected,
                                        onTaskTap: _handleTaskTap,
                                        showTopBorder: week != 0,
                                        capLanesToFit: true,
                                        taskmasterOn: _taskmasterOn,
                                        onTaskDelete: onTaskDelete,
                                        dragRange: dragRange,
                                      ),
                                    ),
                                ],
                              )
                            : _WeekRow(
                                rowStart: _weekStartOf(_anchor),
                                month: _anchor,
                                today: today,
                                tasks: visibleTasks,
                                projectsById: projectsById,
                                onDayTap: _taskmasterOn
                                    ? (day) => _createTaskForRange(day, day)
                                    : widget.onDaySelected,
                                onTaskTap: _handleTaskTap,
                                dimOutOfRangeDays: false,
                                showTopBorder: false,
                                taskmasterOn: _taskmasterOn,
                                onTaskDelete: onTaskDelete,
                                dragRange: dragRange,
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One week's worth of the grid: a strip of day numbers, then every lane of
/// task bars active that week, stacked below it and scrolling locally if
/// there isn't room for all of them within the row's share of the screen.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.rowStart,
    required this.month,
    required this.today,
    required this.tasks,
    required this.projectsById,
    required this.onDayTap,
    required this.onTaskTap,
    this.dimOutOfRangeDays = true,
    this.showTopBorder = true,
    this.capLanesToFit = false,
    this.taskmasterOn = false,
    required this.onTaskDelete,
    this.dragRange,
  });

  final DateTime rowStart;
  final DateTime month;
  final DateTime today;
  final List<Task> tasks;
  final Map<String, Project> projectsById;
  final ValueChanged<DateTime> onDayTap;
  final void Function(Task task, BuildContext rowContext) onTaskTap;
  final bool dimOutOfRangeDays;
  final bool showTopBorder;

  /// When true (Month view), this row shows as many lanes as actually fit
  /// its allotted height — recomputed on every resize — and collapses the
  /// rest into a per-day "+N more" chip. False (Week view) always shows
  /// every lane in full, scrolling locally if they don't fit, since the
  /// single-week view has more room to spare and a count chip would be
  /// odd there. See [_maxLanesForHeight].
  final bool capLanesToFit;

  final bool taskmasterOn;
  final void Function(Task task) onTaskDelete;

  /// The inclusive [start, end] of a Taskmaster drag-in-progress, if any —
  /// days within it get a highlight tint.
  final (DateTime, DateTime)? dragRange;

  /// The row's own slice of an in-progress Taskmaster drag — null if the
  /// drag (if any) doesn't touch this week at all. Mirrors how a real
  /// multi-week task gets clipped to each row in [_computeLanes]: a true
  /// cap only at the actual drag start/end, square where it continues past
  /// this row's edge.
  ({int colStart, int colEnd, bool roundLeft, bool roundRight})?
  _dragSpanForRow() {
    final range = dragRange;
    if (range == null) return null;
    final rowEnd = _addDays(rowStart, 6);
    final start = range.$1;
    final end = range.$2;
    if (end.isBefore(rowStart) || start.isAfter(rowEnd)) return null;
    final segStart = start.isBefore(rowStart) ? rowStart : start;
    final segEnd = end.isAfter(rowEnd) ? rowEnd : end;
    return (
      colStart: segStart.difference(rowStart).inDays,
      colEnd: segEnd.difference(rowStart).inDays,
      roundLeft: _isSameDay(segStart, start),
      roundRight: _isSameDay(segEnd, end),
    );
  }

  /// The preview widget for a drag span clipped to this row, always built
  /// as a [_CalendarCrossingPill] — even for a plain, non-crossing span —
  /// so the same widget (and `State`) persists for an entire drag rather
  /// than swapping types the instant the weekday/weekend split changes.
  /// [_CalendarCrossingPill] already renders a plain span identically to a
  /// bare pill (its own geometry collapses to one when there's no weekend
  /// connector to draw), so nothing looks different in that case — but
  /// shrinking back out of a weekend no longer has a one-frame "reset to a
  /// fresh, full-width pill" flash the way swapping to a separate widget
  /// did: that swap discarded this element's `State` (and restarted its
  /// entrance pop) at the exact moment the box's `AnimatedPositioned` width
  /// was still mid-tween down from the wider, weekend-inclusive span.
  Widget _buildGhost(
    ({int colStart, int colEnd, bool roundLeft, bool roundRight}) dragSpan,
    double colWidth,
  ) {
    final split = _weekendSplit(dragSpan.colStart, dragSpan.colEnd);
    final leadingTaper = !dragSpan.roundLeft;
    return _CalendarCrossingPill(
      colWidth: colWidth,
      weekdayCols: split.weekdayCols,
      weekendCols: split.weekendCols,
      leadingTaper: leadingTaper,
      roundLeft: dragSpan.roundLeft,
      roundRight: dragSpan.roundRight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final rowEnd = _addDays(rowStart, 6);
    final lanes = _computeLanes(tasks, rowStart, rowEnd);
    final dragSpan = _dragSpanForRow();
    // The preview must never sit on top of a real task pill, so it claims
    // the first lane that isn't already occupied across its own column
    // span — exactly the same rule real tasks use to find a lane, just
    // evaluated against the already-placed real tasks only (the ghost
    // itself never perturbs their lanes).
    int? ghostLane;
    if (dragSpan != null) {
      ghostLane = lanes.length;
      for (var i = 0; i < lanes.length; i++) {
        final occupied = lanes[i].any(
          (p) => dragSpan.colStart <= p.colEnd && dragSpan.colEnd >= p.colStart,
        );
        if (!occupied) {
          ghostLane = i;
          break;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        border: showTopBorder
            ? Border(top: BorderSide(color: tokens.edge))
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colWidth = constraints.maxWidth / 7;
          final compactCells = colWidth < _compactCellWidth;

          // Recomputed on every resize, using this row's actual available
          // height — see _maxLanesForHeight.
          final cap = capLanesToFit
              ? _maxLanesForHeight(constraints.maxHeight, lanes.length)
              : null;
          final overflow = cap != null && lanes.length > cap;
          // All [cap] lanes always show in full — the "+N more" chip is an
          // extra row appended below them, not a slot borrowed from the cap.
          final visibleLanes = cap != null
              ? lanes.sublist(0, math.min(cap, lanes.length))
              : lanes;
          final hiddenLanes = overflow
              ? lanes.sublist(cap)
              : const <List<_BarPlacement>>[];
          final overflowCounts = List<int>.generate(
            7,
            (day) => hiddenLanes
                .where(
                  (lane) =>
                      lane.any((p) => p.colStart <= day && p.colEnd >= day),
                )
                .length,
          );

          return Stack(
            children: [
              // A background+divider layer sized to the full row, independent
              // of the day-number/lane content layered on top — so weekend and
              // next-month shading, and the lines between days, run the row's
              // whole height rather than just behind the day numbers.
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: _DayCellBackground(
                          inCurrentMonth:
                              !dimOutOfRangeDays ||
                              _addDays(rowStart, i).month == month.month,
                          isWeekend: i == 5 || i == 6,
                          isToday: _isSameDay(_addDays(rowStart, i), today),
                          showDivider: i < 6,
                          isDragSelected:
                              dragRange != null &&
                              !_addDays(rowStart, i).isBefore(dragRange!.$1) &&
                              !_addDays(rowStart, i).isAfter(dragRange!.$2),
                        ),
                      ),
                  ],
                ),
              ),
              if (compactCells)
                Positioned.fill(
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: _CompactDay(
                            date: _addDays(rowStart, i),
                            active:
                                !dimOutOfRangeDays ||
                                _addDays(rowStart, i).month == month.month,
                            isToday: _isSameDay(_addDays(rowStart, i), today),
                            dayTasks: _tasksOnDay(tasks, _addDays(rowStart, i)),
                            today: today,
                            onTap: () => onDayTap(_addDays(rowStart, i)),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: _DayNumber(
                                date: _addDays(rowStart, i),
                                active:
                                    !dimOutOfRangeDays ||
                                    _addDays(rowStart, i).month == month.month,
                                isToday: _isSameDay(
                                  _addDays(rowStart, i),
                                  today,
                                ),
                                onTap: () => onDayTap(_addDays(rowStart, i)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final lane in visibleLanes) ...[
                                _LaneRow(
                                  lane: lane,
                                  today: today,
                                  projectsById: projectsById,
                                  onTaskTap: onTaskTap,
                                  taskmasterOn: taskmasterOn,
                                  onTaskDelete: onTaskDelete,
                                  colWidth: colWidth,
                                ),
                                const SizedBox(height: 3),
                              ],
                              if (overflow)
                                _OverflowRow(
                                  rowStart: rowStart,
                                  counts: overflowCounts,
                                  tasks: tasks,
                                  projectsById: projectsById,
                                  onTaskTap: onTaskTap,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Compact cells have no bars; the drag tint on the days is the
              // preview there.
              if (dragSpan != null && !compactCells)
                AnimatedPositioned(
                  key: const ValueKey('drag-ghost'),
                  duration: _dragGhostAnimationDuration,
                  curve: Curves.easeOut,
                  left: dragSpan.colStart * colWidth + 2,
                  width:
                      (dragSpan.colEnd - dragSpan.colStart + 1) * colWidth - 4,
                  // Lane 0 sits just under the day-number row; each lane
                  // below it adds its own height, so the preview lines up
                  // with whichever lane it actually claimed above.
                  top: _rowTopInset + (ghostLane ?? 0) * _laneHeight,
                  height: 27,
                  child: IgnorePointer(child: _buildGhost(dragSpan, colWidth)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// How many lanes of real task pills fit within [availableHeight] (a Month
/// row's actual height for this layout pass), out of [totalLanes] active
/// that week — recomputed on every resize so the visible count tracks the
/// window instead of being fixed. Uses the exact pixel geometry the row
/// itself lays out with (see the `_row*`/`_lane*`/`_overflowChipHeight`
/// consts up top), so this always agrees with what actually fits on
/// screen rather than an approximation.
int _maxLanesForHeight(double availableHeight, int totalLanes) {
  final fitsEverything =
      _rowTopInset + totalLanes * _laneHeight + _rowBottomPadding <=
      availableHeight;
  if (fitsEverything) return totalLanes;

  // Doesn't all fit — one of the slots freed up has to become the "+N
  // more" chip instead of a lane, so this is always < totalLanes.
  final withChip =
      (availableHeight -
          _rowTopInset -
          _overflowChipHeight -
          _rowBottomPadding) /
      _laneHeight;
  return withChip.floor().clamp(0, totalLanes - 1);
}

/// One day column's full-height backdrop: shades weekends and days outside
/// the month being viewed, and draws the dividing line to its right.
class _DayCellBackground extends StatelessWidget {
  const _DayCellBackground({
    required this.inCurrentMonth,
    required this.isWeekend,
    this.isToday = false,
    required this.showDivider,
    this.isDragSelected = false,
  });

  final bool inCurrentMonth;
  final bool isWeekend;
  final bool isToday;
  final bool showDivider;
  final bool isDragSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;

    // Out-of-month days and weekends are quiet neutral washes (no texture);
    // the weekend one is lighter so the two stay distinguishable.
    final Widget fill = !inCurrentMonth
        ? ColoredBox(color: tokens.raised)
        : (isWeekend
              ? ColoredBox(color: tokens.raised.withValues(alpha: 0.5))
              : const SizedBox.expand());

    // The divider is painted as a foreground decoration so it stays on
    // top of the fill.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isToday
            ? Border.all(color: accent, width: 1.5)
            : (showDivider
                  ? Border(right: BorderSide(color: tokens.edge))
                  : null),
      ),
      position: DecorationPosition.foreground,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            fill,
            if (isDragSelected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The day-of-month numeral; today is an accent-filled circle.
class _DayBadge extends StatelessWidget {
  const _DayBadge({
    required this.date,
    required this.active,
    required this.isToday,
  });

  final DateTime date;
  final bool active;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isToday ? accent : null,
        shape: BoxShape.circle,
      ),
      child: Text(
        '${date.day}',
        style: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
          color: isToday
              ? (accent.computeLuminance() > 0.5 ? Colors.black : Colors.white)
              : (active ? tokens.neutral200 : tokens.neutral500),
        ),
      ),
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({
    required this.date,
    required this.active,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final bool active;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NocturneRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Center(
          child: _DayBadge(date: date, active: active, isToday: isToday),
        ),
      ),
    );
  }
}

/// A day cell too narrow for task bars: the day number, then one dot per
/// task (as many as fit) and a "+N" for the rest. A red glyph marks a day
/// with an overdue task, so the dots never carry that alone. The whole cell
/// does what tapping the day number does.
class _CompactDay extends StatelessWidget {
  const _CompactDay({
    required this.date,
    required this.active,
    required this.isToday,
    required this.dayTasks,
    required this.today,
    required this.onTap,
  });

  final DateTime date;
  final bool active;
  final bool isToday;
  final List<Task> dayTasks;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final n = dayTasks.length;
    final overdue = dayTasks.any(
      (t) =>
          !t.isChecked &&
          _dateOnly(t.dueDateEnd ?? t.dueDate!).isBefore(_dateOnly(today)),
    );
    final dotColors = [
      for (final t in dayTasks)
        t.isChecked
            ? tokens.neutral600
            : (_dateOnly(t.dueDateEnd ?? t.dueDate!).isBefore(_dateOnly(today))
                  ? tokens.danger
                  : accent),
    ];
    return Semantics(
      button: true,
      label:
          '${_monthNames[date.month - 1]} ${date.day}, '
          '$n ${n == 1 ? 'task' : 'tasks'}',
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, c) {
            const dot = 6.0, gap = 3.0, header = 28.0;
            final perRow = math.max(
              1,
              ((c.maxWidth - 4) / (dot + gap)).floor(),
            );
            final lines = math.max(
              1,
              ((c.maxHeight - header) / (dot + gap)).floor(),
            );
            final capacity = perRow * lines;
            // A "+N" label takes about two dot slots.
            final shown = n <= capacity ? n : math.max(0, capacity - 2);
            return ClipRect(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
                child: Column(
                  children: [
                    _DayBadge(date: date, active: active, isToday: isToday),
                    const SizedBox(height: 2),
                    if (overdue)
                      Icon(Icons.error_outline, size: 10, color: tokens.danger),
                    if (n > 0)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (var i = 0; i < shown; i++)
                            Container(
                              width: dot,
                              height: dot,
                              decoration: BoxDecoration(
                                color: dotColors[i],
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (n > shown)
                            Text(
                              '+${n - shown}',
                              style: TextStyle(
                                fontSize: 10,
                                height: 6 / 10,
                                fontWeight: FontWeight.w600,
                                color: tokens.neutral400,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One stacking lane's worth of columns: bars that fall in this lane,
/// spanning the week's columns they cover, with equal-width empty slots
/// filling the rest so every lane lines up with the day-number row above.
class _LaneRow extends StatelessWidget {
  const _LaneRow({
    required this.lane,
    required this.today,
    required this.projectsById,
    required this.onTaskTap,
    required this.taskmasterOn,
    required this.onTaskDelete,
    required this.colWidth,
  });

  final List<_BarPlacement> lane;
  final DateTime today;
  final Map<String, Project> projectsById;
  final void Function(Task task, BuildContext rowContext) onTaskTap;
  final bool taskmasterOn;
  final void Function(Task task) onTaskDelete;

  /// The pixel width of one grid column — passed down (rather than relying
  /// on this row's own flex layout) so a crossing pill's weekday/weekend
  /// taper lands at an exact, grid-anchored pixel offset instead of a
  /// fraction of whatever width flex happens to hand it.
  final double colWidth;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var col = 0;
    for (final placement in lane) {
      if (placement.colStart > col) {
        children.add(
          Expanded(flex: placement.colStart - col, child: const SizedBox()),
        );
      }
      final span = placement.colEnd - placement.colStart + 1;
      final split = _weekendSplit(placement.colStart, placement.colEnd);
      // Every row is Monday-through-Sunday, so a placement that doesn't
      // start in this row (it started in an earlier week) necessarily
      // picks up right after last row's Sunday — always a weekend hand-off,
      // even when this row's own segment never reaches its own weekend.
      final leadingTaper = !placement.isRangeStart;
      children.add(
        Expanded(
          flex: span,
          child: split.weekendCols > 0 || leadingTaper
              ? _buildCrossingBar(placement, split, leadingTaper)
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  child: _TaskBar(
                    placement: placement,
                    today: today,
                    project: projectsById[placement.task.projectId],
                    onTap: (ctx) => onTaskTap(placement.task, ctx),
                    taskmasterOn: taskmasterOn,
                    onDelete: () => onTaskDelete(placement.task),
                    roundLeft: placement.isRangeStart,
                    roundRight: placement.isRangeEnd,
                  ),
                ),
        ),
      );
      col = placement.colEnd + 1;
    }
    if (col < 7) {
      children.add(Expanded(flex: 7 - col, child: const SizedBox()));
    }
    return Row(children: children);
  }

  /// A placement that runs from a weekday into its own weekend, or that
  /// picks up from a weekend the previous row left off in, renders as one
  /// continuous [_CalendarCrossingPill] — its shape tapers from the normal
  /// pill height down to (or up from) a slim weekend connector through its
  /// own contour, rather than being split into separate touching widgets.
  Widget _buildCrossingBar(
    _BarPlacement placement,
    ({int weekdayCols, int weekendCols}) split,
    bool leadingTaper,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: _CalendarCrossingPill(
        colWidth: colWidth,
        weekdayCols: split.weekdayCols,
        weekendCols: split.weekendCols,
        leadingTaper: leadingTaper,
        roundLeft: placement.isRangeStart,
        roundRight: placement.isRangeEnd,
        task: placement.task,
        project: projectsById[placement.task.projectId],
        today: today,
        onTap: (ctx) => onTaskTap(placement.task, ctx),
        taskmasterOn: taskmasterOn,
        onDelete: () => onTaskDelete(placement.task),
      ),
    );
  }
}

/// The row below a capped set of lanes: one cell per day showing a "+N"
/// chip when that day has tasks hidden beyond the visible lanes — tapping
/// it opens the full list of that day's tasks.
class _OverflowRow extends StatelessWidget {
  const _OverflowRow({
    required this.rowStart,
    required this.counts,
    required this.tasks,
    required this.projectsById,
    required this.onTaskTap,
  });

  final DateTime rowStart;
  final List<int> counts;
  final List<Task> tasks;
  final Map<String, Project> projectsById;
  final void Function(Task task, BuildContext rowContext) onTaskTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: counts[i] <= 0
                  ? const SizedBox()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            NocturneRadius.sm,
                          ),
                          onTap: () {
                            final day = _addDays(rowStart, i);
                            _showDayTasksDialog(
                              context,
                              day,
                              _tasksOnDay(tasks, day),
                              projectsById,
                              onTaskTap,
                            );
                          },
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '+${counts[i]} more',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: tokens.neutral400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Every task active on [day], unchecked first and then by title — the
/// order shown in the overflow popup.
List<Task> _tasksOnDay(List<Task> tasks, DateTime day) {
  final result = tasks.where((task) {
    if (task.dueDate == null) return false;
    final start = _dateOnly(task.dueDate!);
    final end = task.dueDateEnd == null ? start : _dateOnly(task.dueDateEnd!);
    return !day.isBefore(start) && !day.isAfter(end);
  }).toList();
  result.sort((a, b) {
    if (a.isChecked != b.isChecked) return a.isChecked ? 1 : -1;
    return a.title.compareTo(b.title);
  });
  return result;
}

void _showDayTasksDialog(
  BuildContext context,
  DateTime day,
  List<Task> dayTasks,
  Map<String, Project> projectsById,
  void Function(Task task, BuildContext rowContext) onTaskTap,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_monthNames[day.month - 1]} ${day.day}, ${day.year}',
                        style: Theme.of(dialogContext).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: dayTasks.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: NocturneSpace.s2),
                    itemBuilder: (_, index) {
                      final task = dayTasks[index];
                      final placement = _BarPlacement(
                        task: task,
                        colStart: 0,
                        colEnd: 0,
                        isRangeStart: true,
                        isRangeEnd: true,
                      );
                      return _TaskBar(
                        placement: placement,
                        today: DateTime.now(),
                        project: projectsById[task.projectId],
                        onTap: (_) {
                          Navigator.of(dialogContext).pop();
                          // Hands back the calling page's context, not the
                          // dialog's — that one unmounts the moment it pops.
                          onTaskTap(task, context);
                        },
                        taskmasterOn: false,
                        onDelete: () {},
                        roundLeft: true,
                        roundRight: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TaskBar extends StatefulWidget {
  const _TaskBar({
    required this.placement,
    required this.today,
    required this.project,
    required this.onTap,
    required this.taskmasterOn,
    required this.onDelete,
    required this.roundLeft,
    required this.roundRight,
  });

  final _BarPlacement placement;
  final DateTime today;
  final Project? project;
  final void Function(BuildContext rowContext) onTap;
  final bool taskmasterOn;
  final VoidCallback onDelete;

  /// Whether this bar's left/right edge gets the pill's rounded cap — false
  /// at a row's edge where the task actually continues into the next or
  /// previous week, rather than truly starting or ending there.
  final bool roundLeft;
  final bool roundRight;

  @override
  State<_TaskBar> createState() => _TaskBarState();
}

class _TaskBarState extends State<_TaskBar> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.placement.task;
    final style = _resolveTaskBarStyle(
      context,
      task,
      widget.project,
      widget.today,
    );

    final radius = BorderRadius.horizontal(
      left: widget.roundLeft ? const Radius.circular(_barRadius) : Radius.zero,
      right: widget.roundRight
          ? const Radius.circular(_barRadius)
          : Radius.zero,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: 27,
        child: Material(
          color: style.bg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: style.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onTap(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: _taskBarContentRow(
                style: style,
                task: task,
                taskmasterOn: widget.taskmasterOn,
                hovering: _hovering,
                onDelete: widget.onDelete,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The resolved colors/labels a task's bar renders with, shared by
/// [_TaskBar] and [_CalendarCrossingPill] so a weekend-crossing pill looks
/// exactly like its non-crossing counterpart would for the same task.
class _TaskBarStyle {
  const _TaskBarStyle({
    required this.bg,
    required this.fg,
    required this.border,
    required this.originColor,
    required this.originLabel,
    required this.priorityColor,
    required this.isOverdue,
    required this.dangerColor,
  });

  final Color bg;
  final Color fg;
  final Color border;
  final Color originColor;
  final String originLabel;
  final Color? priorityColor;
  final bool isOverdue;
  final Color dangerColor;
}

_TaskBarStyle _resolveTaskBarStyle(
  BuildContext context,
  Task task,
  Project? project,
  DateTime today,
) {
  final tokens = context.nocturne;
  final overallEnd = task.dueDateEnd ?? task.dueDate!;
  final isOverdue =
      !task.isChecked && _dateOnly(overallEnd).isBefore(_dateOnly(today));

  // Colour is meaning: overdue is red, due within two days is amber, anything
  // else is a quiet neutral bar. Done stays neutral (struck through).
  final isSoon =
      !task.isChecked &&
      !isOverdue &&
      !_dateOnly(overallEnd).isAfter(_addDays(_dateOnly(today), 2));
  final statusColor = task.isChecked
      ? tokens.neutral500
      : (isOverdue ? tokens.danger : (isSoon ? tokens.warn : null));
  // Blended onto the opaque surface (not left translucent) so the grid lines
  // behind a bar never show through it.
  final bg = statusColor == null || task.isChecked
      ? tokens.raised
      : Color.alphaBlend(
          statusColor.withValues(alpha: tokens.isDark ? 0.18 : 0.12),
          tokens.surface,
        );
  // Darkened on enamel so project-coloured legends stay readable on the tint.
  final originColor = project != null
      ? (tokens.isDark
            ? accentPalette[project.colorIndex]
            : Color.lerp(accentPalette[project.colorIndex], Colors.black, 0.4)!)
      : tokens.neutral500;

  return _TaskBarStyle(
    bg: bg,
    fg: task.isChecked ? tokens.neutral500 : tokens.text,
    border: statusColor == null || task.isChecked
        ? tokens.borderStrong
        : statusColor.withValues(alpha: 0.7),
    originColor: originColor,
    originLabel: project != null ? project.name : 'Unfiled',
    priorityColor: switch (task.priority) {
      TaskPriority.high => NocturnePriority.high,
      TaskPriority.med => NocturnePriority.med,
      TaskPriority.low => NocturnePriority.low,
      TaskPriority.none => null,
    },
    isOverdue: isOverdue,
    dangerColor: tokens.danger,
  );
}

/// The icon/text row shown inside a task's bar — identical whether that bar
/// is a plain [_TaskBar] or the weekday portion of a [_CalendarCrossingPill].
Widget _taskBarContentRow({
  required _TaskBarStyle style,
  required Task task,
  required bool taskmasterOn,
  required bool hovering,
  required VoidCallback onDelete,
}) {
  final project = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.folder, size: 13, color: style.originColor),
      const SizedBox(width: 4),
    ],
  );
  Widget titleText() => Text(
    task.title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 13,
      height: 20 / 13,
      fontWeight: FontWeight.w500,
      color: style.fg,
      decoration: task.isChecked ? TextDecoration.lineThrough : null,
    ),
  );
  final lead = <Widget>[
    if (style.isOverdue) ...[
      Icon(Icons.error_outline, size: 13, color: style.dangerColor),
      const SizedBox(width: 4),
    ],
    if (style.priorityColor != null) ...[
      Icon(Icons.flag, size: 12, color: style.priorityColor),
      const SizedBox(width: 4),
    ],
  ];
  final tail = <Widget>[
    if (task.hasSubtasks) ...[
      const SizedBox(width: 4),
      Icon(Icons.checklist, size: 13, color: style.fg.withValues(alpha: 0.85)),
    ],
    if (taskmasterOn && hovering) ...[
      const SizedBox(width: 4),
      _DeleteDot(onTap: onDelete),
    ],
  ];

  return LayoutBuilder(
    builder: (context, constraints) {
      // Too narrow for "project  title": drop the project label (its folder
      // icon stays, in the project's colour) and give the room to the title.
      final narrow = constraints.maxWidth < 150;
      return Row(
        children: [
          ...lead,
          project,
          if (!narrow) ...[
            Expanded(
              flex: 2,
              child: Text(
                style.originLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: style.originColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(flex: 3, child: titleText()),
          ...tail,
        ],
      );
    },
  );
}

/// The small "x" that appears at a bar's trailing edge, in Taskmaster
/// mode, once the pointer hovers it — a quick way to delete the task
/// without opening it first.
class _DeleteDot extends StatelessWidget {
  const _DeleteDot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final danger = context.nocturne.danger;
    return Material(
      color: danger.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.close, size: 12, color: danger),
        ),
      ),
    );
  }
}

/// The outline of a task bar that runs from a weekday into its own weekend,
/// or that picks up a weekend hand-off from the row above: the weekday
/// portion is a normal, undeformed rounded pill (never cut or tapered), and
/// a separate, thinner connector bar is unioned onto it wherever the task
/// continues into a weekend — overlapping back into the pill's own rounded
/// cap region so it reads as emerging from that cap's curve, rather than
/// the pill itself changing shape.
///
/// [weekdayCols]/[weekendCols]/[colWidth] place the weekday/weekend
/// boundary at a fixed pixel offset from the box's own left edge —
/// `weekdayCols * colWidth`, the same 2px-inset convention every crossing
/// pill is drawn with — rather than a fraction of the box's own (possibly
/// still mid-animation, while a drag is growing it) width. That keeps the
/// boundary pinned to its grid column line at every frame instead of
/// drifting while the box's far edge eases toward its new size.
class _CrossingPillBorder extends OutlinedBorder {
  const _CrossingPillBorder({
    required this.colWidth,
    required this.weekdayCols,
    required this.weekendCols,
    required this.allowTrailingLinger,
    required this.leadingTaper,
    required this.weekdayHeight,
    required this.weekendHeight,
    required this.roundLeft,
    required this.roundRight,
    super.side = BorderSide.none,
  });

  final double colWidth;
  final int weekdayCols;
  final int weekendCols;

  /// Whether the trailing connector is allowed to keep rendering (tracking
  /// the box's own, still-animating width) even once [weekendCols] itself
  /// has already dropped to 0 — true only for the one rebuild right after
  /// a drag shrinks back out of its own weekend, so a *plain* weekday span
  /// shrinking (which never had a connector to begin with) never grows one
  /// just because its box also happens to be animating narrower. Set by
  /// [_CalendarCrossingPillState], which is the one place that can compare
  /// this build's [weekendCols] against the previous one's.
  final bool allowTrailingLinger;

  /// True when this box's own left edge picks up mid-taper from a weekend
  /// the previous row's segment ended in — the mirror image of the normal
  /// weekday→weekend taper, just starting at thin height right at x=0
  /// instead of narrowing into it.
  final bool leadingTaper;
  final double weekdayHeight;
  final double weekendHeight;
  final bool roundLeft;
  final bool roundRight;

  @override
  _CrossingPillBorder copyWith({BorderSide? side}) => _CrossingPillBorder(
    colWidth: colWidth,
    weekdayCols: weekdayCols,
    weekendCols: weekendCols,
    allowTrailingLinger: allowTrailingLinger,
    leadingTaper: leadingTaper,
    weekdayHeight: weekdayHeight,
    weekendHeight: weekendHeight,
    roundLeft: roundLeft,
    roundRight: roundRight,
    side: side ?? this.side,
  );

  double _capRadius(bool thin) =>
      math.min(_barRadius, (thin ? weekendHeight : weekdayHeight) / 2);

  /// Visible length of the thin leading connector before it's absorbed into
  /// the pill's own left cap — there's no real grid boundary to anchor this
  /// side to (unlike [neckMid] on the trailing side), so it's a fixed,
  /// purely cosmetic length. [_CalendarCrossingPillState] uses the same
  /// value to inset its content past this connector.
  static const double leadConnectorLength = 16.0;

  Path _buildPath(Rect rect) {
    final fullTop = rect.top + (rect.height - weekdayHeight) / 2;
    final fullBottom = fullTop + weekdayHeight;
    final thinTop = rect.top + (rect.height - weekendHeight) / 2;
    final thinBottom = thinTop + weekendHeight;
    final thinCapR = _capRadius(true);

    // A span entirely within the weekend (e.g. a task or drag that starts
    // directly on a Saturday) has no weekday portion to provide a pill for
    // either end to be capped by, so it's just the thin shape by itself,
    // capped the same way the weekday pill normally would be at a true end.
    if (weekdayCols <= 0) {
      return Path()..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(rect.left, thinTop, rect.right, thinBottom),
          topLeft: roundLeft ? Radius.circular(thinCapR) : Radius.zero,
          bottomLeft: roundLeft ? Radius.circular(thinCapR) : Radius.zero,
          topRight: roundRight ? Radius.circular(thinCapR) : Radius.zero,
          bottomRight: roundRight ? Radius.circular(thinCapR) : Radius.zero,
        ),
      );
    }

    // The weekday/weekend boundary's absolute position, independent of the
    // box's own current width (see the class doc). While a drag shrinks
    // back out of its own weekend, [weekendCols] drops to 0 the instant the
    // pointer crosses back onto a weekday, but the box's
    // `AnimatedPositioned` width takes another 150ms to tween down to the
    // new, weekend-less span — so for that whole stretch the box is still
    // visibly wider than the boundary, and (when [allowTrailingLinger] says
    // this is genuinely that case, not just a plain weekday span shrinking
    // on its own) the connector keeps rendering, shrinking smoothly along
    // with the box, instead of vanishing instantly into a full-width pill.
    final weekdayBoundary = (rect.left + weekdayCols * colWidth - 2).clamp(
      rect.left,
      rect.right,
    );
    final hasTrailingTaper =
        weekendCols > 0 ||
        (allowTrailingLinger && rect.right > weekdayBoundary + 0.5);
    final neckMid = weekdayBoundary;

    final fullCapR = _capRadius(false);
    // How far a thin connector reaches back past the weekday/weekend
    // boundary into the pill's own rounded cap, so the union shows no seam
    // at the cap's tangent point — the thin bar should read as emerging
    // from partway along the cap's curve, not butting flush against it.
    final overlap = fullCapR * 0.9;

    // The weekday portion is always a normal, undeformed rounded pill —
    // both its ends get a full cap regardless of whether that end is a
    // real range boundary or a weekend connector is about to overlap into
    // it, since either way the cap itself should stay visually intact. Each
    // bound is pulled in from the box's own edge whenever a connector is
    // present on that side: the pill's own cap radius is close to half its
    // height, so a cap anchored flush with the box edge would already
    // reach all the way to it and swallow a connector entirely — pulling
    // the bound in leaves room for the thin bar to visibly continue past it.
    final pillLeft = leadingTaper ? rect.left + leadConnectorLength : rect.left;
    final pillRight = hasTrailingTaper ? neckMid : rect.right;
    var path = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(pillLeft, fullTop, pillRight, fullBottom),
          topLeft: Radius.circular(fullCapR),
          bottomLeft: Radius.circular(fullCapR),
          topRight: (hasTrailingTaper || roundRight)
              ? Radius.circular(fullCapR)
              : Radius.zero,
          bottomRight: (hasTrailingTaper || roundRight)
              ? Radius.circular(fullCapR)
              : Radius.zero,
        ),
      );

    if (hasTrailingTaper) {
      final trailLeft = (neckMid - overlap).clamp(rect.left, rect.right);
      path = Path.combine(
        PathOperation.union,
        path,
        Path()..addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(trailLeft, thinTop, rect.right, thinBottom),
            topRight: roundRight ? Radius.circular(thinCapR) : Radius.zero,
            bottomRight: roundRight ? Radius.circular(thinCapR) : Radius.zero,
          ),
        ),
      );
    }

    if (leadingTaper) {
      final leadRight = (pillLeft + overlap).clamp(rect.left, rect.right);
      path = Path.combine(
        PathOperation.union,
        path,
        // The left edge is a continuation cut off by the row boundary, not
        // a real end, so it stays flat — only the pill's own real ends
        // (handled above) ever get a cap.
        Path()..addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(rect.left, thinTop, leadRight, thinBottom),
          ),
        ),
      );
    }

    return path;
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect.deflate(side.width));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_buildPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => this;
}

/// A task bar that spans from a weekday run into its own Saturday/Sunday,
/// and/or picks up a weekend hand-off from the row above, rendered as one
/// continuous [_CrossingPillBorder] shape instead of separate touching
/// widgets — so it reads as a single task continuing through the weekend,
/// never a disconnected block. Also used (with [task] left null) as the
/// Taskmaster drag preview whenever the selected range needs the same
/// treatment, so the live preview already shows the same taper(s) the
/// finished task will have.
class _CalendarCrossingPill extends StatefulWidget {
  const _CalendarCrossingPill({
    required this.colWidth,
    required this.weekdayCols,
    required this.weekendCols,
    required this.roundLeft,
    required this.roundRight,
    this.leadingTaper = false,
    this.task,
    this.project,
    this.today,
    this.onTap,
    this.taskmasterOn = false,
    this.onDelete,
  });

  final double colWidth;
  final int weekdayCols;
  final int weekendCols;
  final bool roundLeft;
  final bool roundRight;
  final bool leadingTaper;

  /// Null means this is a drag-preview ghost, not a real task.
  final Task? task;
  final Project? project;
  final DateTime? today;
  final void Function(BuildContext rowContext)? onTap;
  final bool taskmasterOn;
  final VoidCallback? onDelete;

  bool get isGhost => task == null;

  @override
  State<_CalendarCrossingPill> createState() => _CalendarCrossingPillState();
}

class _CalendarCrossingPillState extends State<_CalendarCrossingPill> {
  bool _hovering = false;

  static const _weekdayHeight = 27.0;
  static const _weekendHeight = 8.0;

  // How long to keep drawing a trailing weekend connector after [widget]
  // itself has already dropped to weekendCols == 0, so the connector can
  // keep shrinking alongside the box's own [_dragGhostAnimationDuration]
  // width tween instead of vanishing the instant the drag crosses back onto
  // a weekday. A single rebuild's worth of "did the *previous* widget have a
  // weekend" isn't enough: a fast, continuous drag fires several rebuilds
  // (one per pointer-move) within that same still-animating window, and the
  // *second* one already sees a weekend-less previous widget too — clearing
  // the linger before the box has actually caught up, and flashing straight
  // to a full-width weekday pill. Tracking wall-clock time since the real
  // exit instead survives any number of rebuilds inside the window.
  DateTime? _weekendLingerUntil;

  bool get _allowTrailingLinger {
    final until = _weekendLingerUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  void didUpdateWidget(covariant _CalendarCrossingPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.weekendCols > 0) {
      // Genuinely back in the weekend — the shape's own `weekendCols > 0`
      // branch handles this directly, no lingering needed.
      _weekendLingerUntil = null;
    } else if (oldWidget.weekendCols > 0) {
      _weekendLingerUntil = DateTime.now().add(_dragGhostAnimationDuration);
    }
    // A plain weekday-to-weekday rebuild (both old and new weekendCols == 0)
    // leaves an already-running linger window untouched.
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;

    final Color bg;
    final Color border;
    final double sideWidth;
    final Widget content;
    if (widget.isGhost) {
      bg = Color.alphaBlend(accent.withValues(alpha: 0.18), tokens.surface);
      border = accent.withValues(alpha: 0.8);
      sideWidth = 1.4;
      content = Row(
        children: [
          Icon(Icons.add, size: 13, color: accent),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'New task',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      );
    } else {
      final style = _resolveTaskBarStyle(
        context,
        widget.task!,
        widget.project,
        widget.today!,
      );
      bg = style.bg;
      border = style.border;
      sideWidth = 1;
      content = _taskBarContentRow(
        style: style,
        task: widget.task!,
        taskmasterOn: widget.taskmasterOn,
        hovering: _hovering,
        onDelete: widget.onDelete ?? () {},
      );
    }

    final shape = _CrossingPillBorder(
      colWidth: widget.colWidth,
      weekdayCols: widget.weekdayCols,
      weekendCols: widget.weekendCols,
      allowTrailingLinger: _allowTrailingLinger,
      leadingTaper: widget.leadingTaper,
      weekdayHeight: _weekdayHeight,
      weekendHeight: _weekendHeight,
      roundLeft: widget.roundLeft,
      roundRight: widget.roundRight,
      side: BorderSide(color: border, width: sideWidth),
    );

    // Mirrors the shape's own math: content lives in the full-height
    // pill region only, inset past the leading connector (if any) — the
    // thin weekend bar is too narrow to hold a label either way.
    final leadInset = widget.leadingTaper
        ? _CrossingPillBorder.leadConnectorLength
        : 0.0;
    final contentWidth = math.max(
      0.0,
      widget.weekdayCols * widget.colWidth - 2 - leadInset,
    );

    Widget pill = SizedBox(
      height: _weekdayHeight,
      child: Material(
        color: bg,
        shape: shape,
        // `_CrossingPillBorder` doesn't override lerpFrom/lerpTo, so
        // Material's own default shape animation (200ms unless told
        // otherwise) falls back to abruptly swapping between the old and
        // new border instance partway through — completely unsynced from
        // the box's own 150ms AnimatedPositioned width tween above. For one
        // or two frames that leaves the OLD (narrower) weekdayCols/
        // weekendCols split painting into the NEW (already-growing) rect,
        // which is what produced the brief full-height flash when a drag
        // first extends into the weekend. The shape's own math already
        // handles the visual transition smoothly frame-to-frame as `rect`
        // grows, so Material's redundant animation only needs to be turned
        // off, not replaced.
        animationDuration: Duration.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.isGhost ? null : () => widget.onTap?.call(context),
          child: Stack(
            children: [
              Positioned(
                left: leadInset,
                top: 0,
                bottom: 0,
                width: contentWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.isGhost) {
      pill = MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: pill,
      );
    } else {
      // A fresh drag's very first frame should still pop in, same as
      // before this widget also took over the plain (non-crossing) ghost
      // case — but only once: a TweenAnimationBuilder with an unchanging
      // begin/end doesn't replay on the rebuilds a live drag causes every
      // time the pointer moves.
      pill = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        builder: (context, scale, child) =>
            Opacity(opacity: scale, child: child),
        child: pill,
      );
    }
    return pill;
  }
}

/// Where one task's bar lands within a single week row: which columns
/// (0-6) it spans in *this* row, and whether those ends are the task's
/// true start/end (vs. just this row's edge, because the task continues
/// into the next or previous week) — only a true end gets a rounded cap.
class _BarPlacement {
  _BarPlacement({
    required this.task,
    required this.colStart,
    required this.colEnd,
    required this.isRangeStart,
    required this.isRangeEnd,
  });

  final Task task;
  final int colStart;
  final int colEnd;
  final bool isRangeStart;
  final bool isRangeEnd;
}

/// Every task whose due-date span overlaps [rangeStart]..[rangeEnd] at
/// all — a single O(n) pass over the full, unscoped task list, done once
/// per calendar build rather than once per [_WeekRow] (see
/// [CalendarScreen.build]). Uses the same overlap rule as [_computeLanes]
/// itself, just without narrowing to day columns.
List<Task> _tasksOverlappingRange(
  List<Task> tasks,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  return tasks.where((task) {
    if (task.dueDate == null) return false;
    final start = _dateOnly(task.dueDate!);
    final end = task.dueDateEnd == null ? start : _dateOnly(task.dueDateEnd!);
    return !(end.isBefore(rangeStart) || start.isAfter(rangeEnd));
  }).toList();
}

/// Greedily assigns each task active during [rowStart]..[rowEnd] to the
/// first lane whose existing bars don't overlap its column span — longer
/// bars are placed first so a multi-day task claims a stable lane rather
/// than getting split around single-day tasks placed ahead of it. Same-day
/// ties go by [Task.createdAt] rather than title, so adding a new task
/// (via Taskmaster or otherwise) always appends after every task already
/// stacked on that day instead of reshuffling them alphabetically — the
/// existing visible pills keep their lanes exactly as they were, and the
/// new one either lands in the next free lane or, if the day is already
/// full, is the one that pushes the overflow count up.
List<List<_BarPlacement>> _computeLanes(
  List<Task> tasks,
  DateTime rowStart,
  DateTime rowEnd,
) {
  final items = <_BarPlacement>[];
  for (final task in tasks) {
    if (task.dueDate == null) continue;
    final start = _dateOnly(task.dueDate!);
    final end = task.dueDateEnd == null ? start : _dateOnly(task.dueDateEnd!);
    if (end.isBefore(rowStart) || start.isAfter(rowEnd)) continue;

    final segStart = start.isBefore(rowStart) ? rowStart : start;
    final segEnd = end.isAfter(rowEnd) ? rowEnd : end;
    items.add(
      _BarPlacement(
        task: task,
        colStart: segStart.difference(rowStart).inDays,
        colEnd: segEnd.difference(rowStart).inDays,
        isRangeStart: _isSameDay(segStart, start),
        isRangeEnd: _isSameDay(segEnd, end),
      ),
    );
  }

  items.sort((a, b) {
    final spanDiff = (b.colEnd - b.colStart) - (a.colEnd - a.colStart);
    if (spanDiff != 0) return spanDiff;
    if (a.colStart != b.colStart) return a.colStart.compareTo(b.colStart);
    return a.task.createdAt.compareTo(b.task.createdAt);
  });

  final lanes = <List<_BarPlacement>>[];
  for (final item in items) {
    var placed = false;
    for (final lane in lanes) {
      final overlaps = lane.any(
        (p) => item.colStart <= p.colEnd && item.colEnd >= p.colStart,
      );
      if (!overlaps) {
        lane.add(item);
        placed = true;
        break;
      }
    }
    if (!placed) lanes.add([item]);
  }
  for (final lane in lanes) {
    lane.sort((a, b) => a.colStart.compareTo(b.colStart));
  }
  return lanes;
}
