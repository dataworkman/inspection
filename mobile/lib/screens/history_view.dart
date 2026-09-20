import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';
import '../inspections/inspection_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/icon_avatar.dart';
import '../widgets/score_ring.dart';
import '../widgets/status_pill.dart';
import 'inspection_screen.dart';

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    return RefreshIndicator(
      onRefresh: () => inspections.refreshAll(
          includeDashboard: context.read<AuthState>().isAdmin),
      child: inspections.history.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (inspections.listsLoaded)
                  const EmptyState(
                    icon: Icons.history_outlined,
                    title: 'No inspections yet',
                    message:
                        'Finished and in-progress inspections appear here.',
                  ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
              itemCount: inspections.history.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) => _HistoryCard(
                item: inspections.history[index] as Map<String, dynamic>,
              ),
            ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = item['store'] as Map<String, dynamic>;
    final submitted = item['status'] == 'submitted';
    final inspector = (item['inspector'] as Map<String, dynamic>?)?['name'];
    final when =
        parseApiTime(submitted ? item['submitted_at'] : item['created_at']);
    final subtitle = [
      if (when != null)
        '${submitted ? 'Submitted' : 'Started'} ${_phrase(when)}',
      if (inspector != null) inspector.toString(),
    ].join(' - ');

    return AppCard(
      onTap: () => _open(context),
      child: Row(
        children: [
          if (submitted)
            ScoreRing(score: item['score'] as num?, size: 48)
          else
            const IconAvatar(
                icon: Icons.edit_note_outlined, tone: Tone.info, size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store['name'] as String,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (submitted)
            StatusPill(
                label: item['grade']?.toString() ?? 'Submitted',
                tone: toneForGrade(item['grade'] as String?))
          else
            const StatusPill(label: 'In progress', tone: Tone.info),
          const Icon(Icons.chevron_right, color: AppColors.textFaint),
        ],
      ),
    );
  }

  /// "today" / "yesterday" read better mid-sentence than "Today".
  static String _phrase(DateTime when) {
    final text = relativeDay(when);
    return (text == 'Today' || text == 'Yesterday') ? text.toLowerCase() : text;
  }

  Future<void> _open(BuildContext context) async {
    final inspections = context.read<InspectionState>();
    try {
      final inspector = item['inspector'] as Map<String, dynamic>?;
      final resumable = InspectionState.openStatuses.contains(item['status']) &&
          inspector?['id'] == context.read<AuthState>().userId;
      if (resumable) {
        await inspections.resumeInspection(item['id'] as int);
        if (context.mounted) {
          await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InspectionScreen()));
          inspections.loadHistory().ignore();
        }
        return;
      }
      final detail = await inspections.loadInspectionDetail(item['id'] as int);
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InspectionResultScreen(inspection: detail)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open inspection: $error')),
        );
      }
    }
  }
}
