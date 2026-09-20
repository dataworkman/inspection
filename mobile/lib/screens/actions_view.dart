import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';
import '../inspections/inspection_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/icon_avatar.dart';
import '../widgets/status_pill.dart';

class ActionsView extends StatelessWidget {
  const ActionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    return RefreshIndicator(
      onRefresh: () => inspections.refreshAll(
          includeDashboard: context.read<AuthState>().isAdmin),
      child: inspections.actions.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (inspections.listsLoaded || inspections.actions.isEmpty)
                  const EmptyState(
                    icon: Icons.task_alt_outlined,
                    title: 'No corrective actions',
                    message:
                        'Issues raised during inspections are tracked here until they are resolved.',
                  ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
              itemCount: inspections.actions.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final action =
                    inspections.actions[index] as Map<String, dynamic>;
                return _ActionCard(
                  action: action,
                  onTap: () => _showActionSheet(context, action),
                );
              },
            ),
    );
  }

  void _showActionSheet(BuildContext context, Map<String, dynamic> action) {
    final inspections = context.read<InspectionState>();
    final messenger = ScaffoldMessenger.of(context);
    final allowed = correctiveActionStatusesFor(context.read<AuthState>().role);
    final current = action['status'].toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: _ActionSheet(
            action: action,
            allowed: allowed,
            current: current,
            onSelect: (status) async {
              Navigator.of(sheetContext).pop();
              try {
                await inspections.updateActionStatus(
                    action['id'] as int, status);
              } catch (error) {
                messenger.showSnackBar(SnackBar(
                    content: Text('Could not update the action: $error')));
              }
            },
          ),
        ),
      ),
    );
  }
}

DateTime? _dueDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

bool _isOverdue(Map<String, dynamic> action) {
  final due = _dueDate(action['due_date']);
  final status = action['status'];
  if (due == null || status == 'Resolved' || status == 'Verified') return false;
  final today = DateTime.now();
  return due.isBefore(DateTime(today.year, today.month, today.day));
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action, required this.onTap});

  final Map<String, dynamic> action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = action['store'] as Map<String, dynamic>;
    final due = _dueDate(action['due_date']);
    final overdue = _isOverdue(action);
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconAvatar(
            icon: Icons.report_problem_outlined,
            tone: toneForSeverity(action['severity'] as String?),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action['title'] as String,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(store['name'].toString(),
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusPill(
                      label: action['severity'].toString(),
                      tone: toneForSeverity(action['severity'] as String?),
                      dense: true,
                    ),
                    StatusPill(
                      label: action['status'].toString(),
                      tone: toneForActionStatus(action['status'] as String?),
                      dense: true,
                    ),
                    if (due != null)
                      StatusPill(
                        label: overdue
                            ? 'Overdue - ${formatDate(due)}'
                            : 'Due ${formatDate(due)}',
                        tone: overdue ? Tone.danger : Tone.neutral,
                        icon: Icons.event_outlined,
                        dense: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.action,
    required this.allowed,
    required this.current,
    required this.onSelect,
  });

  final Map<String, dynamic> action;
  final List<String> allowed;
  final String current;
  final void Function(String status) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = action['store'] as Map<String, dynamic>;
    final assignee = action['assigned_to'] as Map<String, dynamic>?;
    final description = action['description']?.toString() ?? '';
    final due = _dueDate(action['due_date']);

    Widget detail(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textFaint),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                  width: 84,
                  child: Text(label, style: theme.textTheme.bodySmall)),
              Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(action['title'] as String, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, children: [
          StatusPill(
              label: action['severity'].toString(),
              tone: toneForSeverity(action['severity'] as String?)),
          StatusPill(label: current, tone: toneForActionStatus(current)),
        ]),
        const SizedBox(height: AppSpacing.lg),
        detail(Icons.storefront_outlined, 'Store', store['name'].toString()),
        if (due != null) detail(Icons.event_outlined, 'Due', formatDate(due)),
        if (assignee != null)
          detail(
              Icons.person_outline, 'Assigned to', assignee['name'].toString()),
        if (description.isNotEmpty && description != action['title'])
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(description, style: theme.textTheme.bodyMedium),
          ),
        const Divider(height: AppSpacing.xl * 1.5),
        Text('Set status', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        for (final status in allowed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(status),
            trailing: status == current
                ? const Icon(Icons.check_circle, color: AppColors.primary)
                : const Icon(Icons.radio_button_unchecked,
                    color: AppColors.textFaint),
            onTap: status == current ? null : () => onSelect(status),
          ),
      ],
    );
  }
}
