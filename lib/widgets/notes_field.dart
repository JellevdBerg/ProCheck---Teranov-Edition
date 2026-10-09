import 'package:flutter/material.dart';

/// A multi-line notes text field — shared between [TaskTile]'s expanded
/// detail and the template editor.
class NotesField extends StatelessWidget {
  const NotesField({super.key, required this.controller, this.focusNode});

  final TextEditingController controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: const InputDecoration(labelText: 'Notes', isDense: true),
      minLines: 3,
      maxLines: 6,
    );
  }
}
