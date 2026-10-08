import 'package:uuid/uuid.dart';

import '../models/project.dart';
import '../models/subtask.dart';
import '../models/task.dart';
import '../models/task_priority.dart';

const _uuid = Uuid();

/// A small dataset exercising most of ProCheck's task/project states at
/// once — Settings > Load test data, so verifying a feature doesn't mean
/// hand-building projects, due dates, subtasks, etc. every time. Dates are
/// computed relative to [now] so the data stays useful (today's tasks are
/// always "today") instead of drifting into the past the day after it's
/// loaded.
///
/// Returns the projects and tasks to pass to
/// `projectsProvider.restoreAll`/`tasksProvider.restoreAll`, which — like a
/// backup import — replace everything currently stored.
({List<Project> projects, List<Task> tasks}) buildTestData({
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  DateTime at(int dayOffset, [int hour = 9]) =>
      today.add(Duration(days: dayOffset)).add(Duration(hours: hour));

  final websiteProject = Project(
    id: _uuid.v4(),
    name: 'Website Redesign',
    createdAt: at(-10),
    lastOpenedAt: at(-2),
    colorIndex: 0,
  );
  final launchProject = Project(
    id: _uuid.v4(),
    name: 'Client Launch',
    createdAt: at(-6),
    lastOpenedAt: at(-1),
    colorIndex: 2,
    favorite: true,
  );
  final archivedProject = Project(
    id: _uuid.v4(),
    name: 'Old Onboarding Flow',
    createdAt: at(-60),
    lastOpenedAt: at(-30),
    colorIndex: 4,
    archived: true,
  );

  Subtask sub(String title, {bool checked = false}) =>
      Subtask(id: _uuid.v4(), title: title, isChecked: checked);

  final tasks = <Task>[
    // Website Redesign
    Task(
      id: _uuid.v4(),
      title: 'Design homepage mockup',
      createdAt: at(-9),
      isChecked: true,
      projectId: websiteProject.id,
      priorityIndex: TaskPriority.med.index,
      subtasks: [
        sub('Wireframe', checked: true),
        sub('Get stakeholder approval', checked: true),
      ],
    ),
    Task(
      id: _uuid.v4(),
      title: 'Build nav component',
      createdAt: at(-5),
      dueDate: at(0, 17),
      priorityIndex: TaskPriority.high.index,
      subtasks: [
        sub('Desktop layout', checked: true),
        sub('Mobile layout'),
        sub('Keyboard nav'),
      ],
    ),
    Task(
      id: _uuid.v4(),
      title: 'Write copy for about page',
      createdAt: at(-3),
      dueDate: at(3, 12),
      notes: 'Check tone with marketing before publishing.',
      priorityIndex: TaskPriority.low.index,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Full QA pass',
      createdAt: at(-2),
      dueDate: at(10, 10),
    ),

    // Client Launch (favorite project)
    Task(
      id: _uuid.v4(),
      title: 'Kickoff call',
      createdAt: at(-5),
      isChecked: true,
      dueDate: at(-1, 9),
      projectId: launchProject.id,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Prep + rehearsal week',
      createdAt: at(-4),
      dueDate: at(0, 9),
      dueDateEnd: at(4, 17),
      priorityIndex: TaskPriority.med.index,
      projectId: launchProject.id,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Send signed contract',
      createdAt: at(-8),
      dueDate: at(-5, 17),
      notes: 'Waiting on legal sign-off.',
      priorityIndex: TaskPriority.high.index,
      projectId: launchProject.id,
    ),

    // Archived project — still has its own (mostly completed) tasks
    Task(
      id: _uuid.v4(),
      title: 'Audit old signup flow',
      createdAt: at(-55),
      isChecked: true,
      dueDate: at(-50, 9),
      projectId: archivedProject.id,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Archive onboarding docs',
      createdAt: at(-45),
      isChecked: true,
      dueDate: at(-40, 9),
      projectId: archivedProject.id,
    ),

    // Standalone tasks
    Task(
      id: _uuid.v4(),
      title: 'Daily stretch routine',
      createdAt: at(-20),
      dueDate: at(0, 7),
      notes: '5 minutes, right after waking up.',
      priorityIndex: TaskPriority.low.index,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Weekly team sync',
      createdAt: at(-14),
      dueDate: at(0, 14),
    ),
    Task(
      id: _uuid.v4(),
      title: 'Pay rent',
      createdAt: at(-30),
      dueDate: at(2, 9),
      priorityIndex: TaskPriority.med.index,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Buy groceries',
      createdAt: at(0),
      dueDate: at(0, 18),
      priorityIndex: TaskPriority.med.index,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Submit expense report',
      createdAt: at(-6),
      dueDate: at(-2, 17),
      priorityIndex: TaskPriority.high.index,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Plan birthday party',
      createdAt: at(-4),
      dueDate: at(5, 12),
      priorityIndex: TaskPriority.med.index,
      subtasks: [
        sub('Book venue', checked: true),
        sub('Order cake', checked: true),
        sub('Send invites'),
        sub('Buy decorations'),
      ],
    ),
    Task(
      id: _uuid.v4(),
      title: 'Renew passport',
      createdAt: at(-1),
      dueDate: at(30, 9),
      notes: 'Takes 4-6 weeks — start early.',
    ),
    Task(
      id: _uuid.v4(),
      title: 'Read a book',
      createdAt: at(-1),
      priorityIndex: TaskPriority.low.index,
    ),
    Task(
      id: _uuid.v4(),
      title: 'Finished this one already',
      createdAt: at(-3),
      isChecked: true,
      dueDate: at(-1, 9),
    ),
  ];

  return (
    projects: [websiteProject, launchProject, archivedProject],
    tasks: tasks,
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
