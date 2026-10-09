import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/attachment.dart';
import '../theme/nocturne_theme.dart';
import 'nocturne/nocturne_widgets.dart';
import 'panel/panel.dart';

/// A list of [Attachment] chips plus an "Add attachment" button that opens
/// the native file picker — shared between [TaskTile]'s expanded detail and
/// the template editor, so a template's attachments use the same UI/picker
/// behavior as a task's.
class AttachmentsEditor extends StatelessWidget {
  const AttachmentsEditor({
    super.key,
    required this.attachments,
    required this.onAdd,
    required this.onRemoveAt,
  });

  final List<Attachment> attachments;
  final ValueChanged<List<Attachment>> onAdd;
  final ValueChanged<int> onRemoveAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StampLabel('Attachments', size: 12),
        const SizedBox(height: 6),
        for (var i = 0; i < attachments.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AttachmentChip(
              attachment: attachments[i],
              onRemove: () => onRemoveAt(i),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: NocturneButton(
            label: 'Add attachment',
            icon: Icons.attach_file,
            dense: true,
            onPressed: _pickAttachments,
          ),
        ),
      ],
    );
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;

    onAdd(
      result.files
          .map(
            (f) => Attachment(
              name: f.name,
              size: f.size,
              path: kIsWeb ? null : f.path,
            ),
          )
          .toList(),
    );
  }
}

class AttachmentChip extends StatefulWidget {
  const AttachmentChip({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  State<AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<AttachmentChip> {
  bool _hoveringName = false;
  bool _hoveringRemove = false;

  bool get _canOpen => !kIsWeb && widget.attachment.path != null;

  Future<void> _open(BuildContext context) async {
    final path = widget.attachment.path;
    if (!_canOpen || path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Can't open attachments in the browser — download them instead.",
          ),
        ),
      );
      return;
    }

    final opened = await launchUrl(Uri.file(path));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open "${widget.attachment.name}".')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: panelDecoration(context, depth: PanelDepth.recessed),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 15,
            color: theme.hintColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoveringName = true),
              onExit: (_) => setState(() => _hoveringName = false),
              child: GestureDetector(
                onTap: () => _open(context),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _hoveringName
                        ? context.nocturne.neutral800
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(NocturneRadius.sm),
                  ),
                  child: Text(
                    widget.attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: _canOpen ? TextDecoration.underline : null,
                      decorationColor: theme.hintColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.attachment.sizeLabel,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hoveringRemove = true),
            onExit: (_) => setState(() => _hoveringRemove = false),
            child: GestureDetector(
              onTap: widget.onRemove,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _hoveringRemove
                      ? context.nocturne.danger.withValues(alpha: 0.14)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: _hoveringRemove
                      ? context.nocturne.danger
                      : theme.hintColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
