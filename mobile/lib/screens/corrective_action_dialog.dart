import 'package:flutter/material.dart';

import '../inspections/inspection_state.dart';
import '../utils/format.dart';

class NewCorrectiveAction {
  const NewCorrectiveAction({
    required this.title,
    required this.severity,
    this.description,
    this.dueDate,
  });

  final String title;
  final String severity;
  final String? description;
  final DateTime? dueDate;
}

/// Asks for the details of a corrective action; null when cancelled.
Future<NewCorrectiveAction?> showCorrectiveActionDialog(
  BuildContext context, {
  required String initialTitle,
}) {
  return showDialog<NewCorrectiveAction>(
    context: context,
    builder: (_) => _CorrectiveActionDialog(initialTitle: initialTitle),
  );
}

class _CorrectiveActionDialog extends StatefulWidget {
  const _CorrectiveActionDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_CorrectiveActionDialog> createState() =>
      _CorrectiveActionDialogState();
}

class _CorrectiveActionDialogState extends State<_CorrectiveActionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initialTitle);
  final _description = TextEditingController();
  String _severity = 'Medium';
  DateTime? _dueDate;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New corrective action'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a title'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Details'),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _severity,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: [
                  for (final severity in correctiveActionSeverities)
                    DropdownMenuItem(value: severity, child: Text(severity)),
                ],
                onChanged: (value) =>
                    setState(() => _severity = value ?? _severity),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDueDate,
                      icon: const Icon(Icons.event),
                      label: Text(_dueDate == null
                          ? 'Due date'
                          : 'Due ${formatDate(_dueDate!)}'),
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      onPressed: () => setState(() => _dueDate = null),
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear due date',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final description = _description.text.trim();
    Navigator.of(context).pop(NewCorrectiveAction(
      title: _title.text.trim(),
      severity: _severity,
      description: description.isEmpty ? null : description,
      dueDate: _dueDate,
    ));
  }
}
