import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';
import '../inspections/inspection_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/metric_tile.dart';
import '../widgets/score_ring.dart';
import '../widgets/section_title.dart';
import '../widgets/status_pill.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    final dashboard = inspections.dashboard;
    if (dashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final storeRows = (dashboard['store_ranking'] ??
        dashboard['stores'] ??
        const []) as List<dynamic>;
    final attentionRows =
        (dashboard['attention_required'] ?? const []) as List<dynamic>;
    final average =
        dashboard['average_inspection_score'] ?? dashboard['average_score'];
    final open = (dashboard['open_corrective_actions'] as num?) ?? 0;
    final critical = (dashboard['critical_corrective_actions'] as num?) ?? 0;

    return RefreshIndicator(
      onRefresh: () => inspections.refreshAll(
          includeDashboard: context.read<AuthState>().isAdmin),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
        children: [
          _pair(
            MetricTile(
              label: 'Average score',
              value: '${average ?? '-'}',
              icon: Icons.speed_outlined,
              tone: toneForScore(average as num?),
            ),
            MetricTile(
              label: 'Submitted',
              value: '${dashboard['submitted_inspections'] ?? 0}',
              icon: Icons.assignment_turned_in_outlined,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _pair(
            MetricTile(
              label: 'Open actions',
              value: '$open',
              icon: Icons.task_alt_outlined,
              tone: open > 0 ? Tone.warning : Tone.success,
            ),
            MetricTile(
              label: 'Critical',
              value: '$critical',
              icon: Icons.priority_high_rounded,
              tone: critical > 0 ? Tone.danger : Tone.success,
            ),
          ),
          if (attentionRows.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle('Attention required'),
            for (final raw in attentionRows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _AttentionCard(row: raw as Map<String, dynamic>),
              ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle('Store ranking'),
          if (storeRows.isEmpty)
            const EmptyState(
                icon: Icons.leaderboard_outlined, title: 'No stores yet')
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < storeRows.length; i++) ...[
                    if (i > 0) const Divider(),
                    _RankingRow(
                        rank: i + 1, row: storeRows[i] as Map<String, dynamic>),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pair(Widget left, Widget right) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: right),
          ],
        ),
      );
}

const _reasonLabels = {
  'critical_action': ('Critical action open', Tone.danger),
  'low_score': ('Score below 70', Tone.warning),
  'overdue_action': ('Overdue action', Tone.warning),
  'score_drop': ('Score dropped', Tone.warning),
};

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = row['store'] as Map<String, dynamic>;
    final reasons = ((row['attention_reasons'] as List<dynamic>?) ?? const [])
        .map((r) => _reasonLabels[r])
        .whereType<(String, Tone)>()
        .toList();
    final open = row['open_issues'] ?? 0;
    return AppCard(
      child: Row(
        children: [
          ScoreRing(score: row['latest_score'] as num?, size: 52),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store['name'] as String,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                    'Latest ${row['latest_score'] ?? '-'} / Avg ${row['average_score'] ?? '-'} - $open open ${open == 1 ? 'action' : 'actions'}',
                    style: theme.textTheme.bodySmall),
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final (label, tone) in reasons)
                        StatusPill(label: label, tone: tone, dense: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.rank, required this.row});

  final int rank;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = row['store'] as Map<String, dynamic>;
    final latest = row['latest_score'] as num?;
    final colors = toneColors(toneForScore(latest));
    final submitted = row['submitted_inspections'] ?? 0;
    final open = row['open_issues'] ?? 0;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.surfaceMuted, shape: BoxShape.circle),
            child: Text('$rank',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.textMuted)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store['name'] as String,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                if (latest == null)
                  Text('Not inspected yet', style: theme.textTheme.bodySmall)
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: (latest / 100).clamp(0.0, 1.0).toDouble(),
                      minHeight: 6,
                      color: colors.foreground,
                      backgroundColor: colors.background,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                    'Avg ${row['average_score'] ?? '-'} across $submitted submitted',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(latest == null ? '-' : _score(latest),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: colors.foreground)),
              if (open > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: StatusPill(
                      label: '$open open', tone: Tone.warning, dense: true),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _score(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
