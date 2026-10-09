import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';
import 'nocturne/nocturne_widgets.dart';

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
const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// What [showDueDateCalendarDialog] returns: a single day ([end] null), or
/// an inclusive day range.
class DueDateSelection {
  const DueDateSelection({required this.start, this.end});
  final DateTime start;
  final DateTime? end;
}

/// A single calendar where picking a due date and picking a due-date range
/// are the same gesture, rather than two separate pickers: tap a day to
/// select it; tap a second day and the range between them highlights; tap a
/// third and the oldest of the two currently-selected days drops out, so
/// the range always tracks the two most recently tapped days. Confirming
/// with only one day tapped sets a single due date, same as before.
Future<DueDateSelection?> showDueDateCalendarDialog(
  BuildContext context, {
  DateTime? initialStart,
  DateTime? initialEnd,
}) {
  return showDialog<DueDateSelection>(
    context: context,
    builder: (context) => _DueDateCalendarDialog(
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DueDateCalendarDialog extends StatefulWidget {
  const _DueDateCalendarDialog({this.initialStart, this.initialEnd});

  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  State<_DueDateCalendarDialog> createState() => _DueDateCalendarDialogState();
}

class _DueDateCalendarDialogState extends State<_DueDateCalendarDialog> {
  // Holds at most the 2 most recently tapped days, oldest first — a plain
  // sliding window rather than a richer "start/end" model, since that's
  // exactly the tap-tap-tap behavior this dialog implements.
  final List<DateTime> _taps = [];
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final start = widget.initialStart;
    final end = widget.initialEnd;
    if (start != null) _taps.add(_dateOnly(start));
    if (end != null && !_isSameDay(end, start!)) _taps.add(_dateOnly(end));
    _visibleMonth = _taps.isNotEmpty ? _taps.last : DateTime.now();
  }

  void _handleDayTap(DateTime day) {
    setState(() {
      if (_taps.length >= 2) _taps.removeAt(0);
      _taps.add(day);
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final today = DateTime.now();
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final startOffset = firstOfMonth.weekday % 7;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;

    DateTime? rangeStart;
    DateTime? rangeEnd;
    if (_taps.length == 2) {
      final sorted = [..._taps]..sort();
      rangeStart = sorted[0];
      rangeEnd = sorted[1];
    }

    final helperText = switch (_taps.length) {
      0 => 'Tap a day to set a due date.',
      1 => 'Tap another day to make it a range, or Save for just this day.',
      _ => 'Tap a day to shift the range.',
    };

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(NocturneSpace.s4),
        // Capped, not fixed: a narrow window just gives the dialog less.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _changeMonth(-1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _changeMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: NocturneSpace.s1),
              Text(helperText, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: NocturneSpace.s3),
              Row(
                children: [
                  for (final label in _weekdayLabels)
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tokens.neutral500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                ),
                itemCount: startOffset + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < startOffset) return const SizedBox.shrink();
                  final day = index - startOffset + 1;
                  final date = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month,
                    day,
                  );
                  final isToday = _isSameDay(date, today);
                  final isTapped = _taps.any((t) => _isSameDay(t, date));
                  final inRange =
                      rangeStart != null &&
                      rangeEnd != null &&
                      !date.isBefore(rangeStart) &&
                      !date.isAfter(rangeEnd);

                  final isRangeStart =
                      rangeStart != null && _isSameDay(date, rangeStart);
                  final isRangeEnd =
                      rangeEnd != null && _isSameDay(date, rangeEnd);

                  return InkWell(
                    onTap: () => _handleDayTap(date),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Only the range's actual first/last day gets a
                          // rounded cap; every other in-range cell —
                          // including ones that happen to fall at the start
                          // or end of a week's row — stays square, so the
                          // highlight reads as one continuous bar.
                          if (inRange)
                            Container(
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.horizontal(
                                  left: isRangeStart
                                      ? const Radius.circular(NocturneRadius.lg)
                                      : Radius.zero,
                                  right: isRangeEnd
                                      ? const Radius.circular(NocturneRadius.lg)
                                      : Radius.zero,
                                ),
                              ),
                            ),
                          Container(
                            alignment: Alignment.center,
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: isTapped ? accent : null,
                              shape: BoxShape.circle,
                              border: (!isTapped && isToday)
                                  ? Border.all(color: accent)
                                  : null,
                            ),
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                color: isTapped
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : (isToday ? accent : tokens.neutral200),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: NocturneSpace.s4),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: NocturneSpace.s2,
                runSpacing: NocturneSpace.s2,
                children: [
                  NocturneButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                  ),
                  if (_taps.isNotEmpty)
                    NocturneButton(
                      label: 'Clear',
                      onPressed: () => setState(_taps.clear),
                    ),
                  NocturneButton(
                    label: 'Save',
                    variant: NocturneButtonVariant.primary,
                    onPressed: _taps.isEmpty
                        ? null
                        : () {
                            final sorted = [..._taps]..sort();
                            Navigator.pop(
                              context,
                              DueDateSelection(
                                start: sorted.first,
                                end: sorted.length == 2 ? sorted.last : null,
                              ),
                            );
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
