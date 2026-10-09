import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../providers/settings_provider.dart';
import '../theme/nocturne_theme.dart';
import 'nocturne/nocturne_widgets.dart';
import 'panel/panel.dart';
import 'text_prompt_dialog.dart';

/// The Hero tags a [ProjectCard]'s header shares with the thin bar header of
/// the project's detail screen, so tapping the card morphs it into that bar.
///
/// The icon and the name are split into two independent Hero flights rather
/// than one covering both: the icon's rect-tween looks fine under Flutter's
/// default flight (it's a single glyph), but the name goes from a short
/// horizontal line on the card to a large vertical line in the detail
/// screen's sidebar, and stretching one of those across the animated rect —
/// which is what a single shared Hero does — reads as the text warping or
/// floating mid-flight. See [projectNameHeroFlightShuttleBuilder].
String projectIconHeroTag(String projectId) => 'project-icon-$projectId';

String projectNameHeroTag(String projectId) => 'project-name-$projectId';

/// Crossfades between the two label widgets instead of letting Flutter's
/// default Hero flight stretch one of them across the whole animated rect.
/// Each label is drawn at its own natural orientation/size and simply faded
/// in or out, so neither ever gets distorted mid-flight.
///
/// [reduceMotion] skips the crossfade entirely and jumps straight to the
/// destination label, matching how the rest of the app treats that setting.
HeroFlightShuttleBuilder projectNameHeroFlightShuttleBuilder(
  bool reduceMotion,
) {
  return (
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromHero = fromHeroContext.widget as Hero;
    final toHero = toHeroContext.widget as Hero;

    if (reduceMotion) return toHero.child;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value.clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 1 - t,
              child: Center(child: fromHero.child),
            ),
            Opacity(
              opacity: t,
              child: Center(child: toHero.child),
            ),
          ],
        );
      },
    );
  };
}

/// A project tile for the home screen grid. [featured] gives the tall card
/// with a preview of up to 4 tasks; otherwise it's a compact, name-only
/// chip. Both reveal a delete button on hover.
enum _ProjectCardAction { archive, remove, favorite }

class ProjectCard extends StatefulWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.tasks,
    required this.onTap,
    required this.onDelete,
    required this.onArchive,
    required this.onToggleFavorite,
    this.featured = false,
    this.reduceMotion = false,
  });

  final Project project;
  final List<Task> tasks;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onToggleFavorite;
  final bool featured;
  final bool reduceMotion;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _hovering = false;

  // Opening the menu's full-screen route occludes this card's MouseRegion,
  // which fires onExit and would otherwise flip _hovering back to false —
  // tearing the actions button (and a PopupMenuButton along with it) out of
  // the tree mid-interaction, right as the pending selection is about to
  // come back. Keeping the button visible for as long as its own menu is
  // open — regardless of hover — avoids that, and using a plain showMenu()
  // call anchored on this State (rather than PopupMenuButton's own nested
  // State) means the pending Future is never tied to a widget that hover
  // state could dispose out from under it.
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: widget.featured ? _buildFeatured(context) : _buildCompact(context),
    );
  }

  Widget _header(BuildContext context, {required bool showActions}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Hero(
          tag: projectIconHeroTag(widget.project.id),
          child: Material(
            type: MaterialType.transparency,
            child: Icon(
              Icons.folder,
              color: accentPalette[widget.project.colorIndex],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Hero(
            tag: projectNameHeroTag(widget.project.id),
            flightShuttleBuilder: projectNameHeroFlightShuttleBuilder(
              widget.reduceMotion,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Text(
                widget.project.name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        _actionsMenu(context, visible: showActions || _menuOpen),
      ],
    );
  }

  /// A single "more" button that rolls down a small menu on tap, rather than
  /// separate always-visible icons per action — keeps the hover state tidy
  /// as more actions get added.
  ///
  /// Always laid out (just invisible when [visible] is false) via
  /// [Visibility.maintainSize], so the header's height/width stays constant
  /// across hover — an IconButton's default 48x48 tap target is taller than
  /// the icon/text beside it, and popping it in and out of the tree on
  /// hover was pushing everything below the header down by that difference.
  Widget _actionsMenu(BuildContext context, {required bool visible}) {
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: IconButton(
        icon: Icon(Icons.more_vert, size: 20),
        tooltip: 'Project actions',
        onPressed: () => _openActionsMenu(context),
      ),
    );
  }

  Future<void> _openActionsMenu(BuildContext context) async {
    setState(() => _menuOpen = true);

    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<_ProjectCardAction>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: _ProjectCardAction.favorite,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              widget.project.favorite ? Icons.star : Icons.star_border,
            ),
            title: Text(widget.project.favorite ? 'Unfavorite' : 'Favorite'),
          ),
        ),
        PopupMenuItem(
          value: _ProjectCardAction.archive,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.archive_outlined),
            title: const Text('Archive'),
          ),
        ),
        PopupMenuItem(
          value: _ProjectCardAction.remove,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline),
            title: const Text('Remove'),
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    setState(() => _menuOpen = false);

    switch (action) {
      case _ProjectCardAction.archive:
        widget.onArchive();
      case _ProjectCardAction.remove:
        _confirmDelete(context);
      case _ProjectCardAction.favorite:
        widget.onToggleFavorite();
      case null:
        break;
    }
  }

  Widget _buildFeatured(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.nocturne;
    final preview = widget.tasks.take(4).toList();
    final extra = widget.tasks.length - preview.length;
    final doneCount = widget.tasks.where((t) => t.isChecked).length;
    final totalCount = widget.tasks.length;
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: DecoratedBox(
          // The project's own colour, as a tinted edge on the plate.
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: accentPalette[widget.project.colorIndex],
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, showActions: _hovering),
                if (totalCount > 0) ...[
                  const SizedBox(height: 10),
                  GaugeBar(
                    value: progress,
                    color: accentPalette[widget.project.colorIndex],
                    segments: 16,
                    height: 8,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$doneCount/$totalCount done',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.neutral400,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: preview.isEmpty
                      ? Center(
                          child: Text(
                            'No tasks yet',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final task in preview)
                              _TaskPreviewRow(task: task),
                            if (extra > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '+$extra more',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(context),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(NocturneRadius.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: projectIconHeroTag(widget.project.id),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: accentPalette[widget.project.colorIndex],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Hero(
                      tag: projectNameHeroTag(widget.project.id),
                      flightShuttleBuilder: projectNameHeroFlightShuttleBuilder(
                        widget.reduceMotion,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Text(widget.project.name),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 2),
                _actionsMenu(context, visible: _hovering || _menuOpen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete project?',
      message:
          'Tasks and subtasks inside "${widget.project.name}" will be deleted too. This cannot be undone.',
    );
    if (confirmed) widget.onDelete();
  }
}

class _TaskPreviewRow extends StatelessWidget {
  const _TaskPreviewRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priorityTag = NocturneTag.forPriority(task.priority);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          IndicatorLamp(on: task.isChecked, size: 9),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              task.title,
              style: theme.textTheme.bodySmall?.copyWith(
                decoration: task.isChecked ? TextDecoration.lineThrough : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // ignore: use_null_aware_elements (hive_generator pins analyzer <7, which can't parse `?element`)
          if (priorityTag != null) priorityTag,
          if (task.hasSubtasks)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '${task.completedSubtaskCount}/${task.subtasks.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
