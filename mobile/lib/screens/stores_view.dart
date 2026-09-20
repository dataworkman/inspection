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
import '../widgets/section_title.dart';
import '../widgets/status_pill.dart';
import 'inspection_screen.dart';

class StoreListView extends StatefulWidget {
  const StoreListView({super.key});

  @override
  State<StoreListView> createState() => _StoreListViewState();
}

class _StoreListViewState extends State<StoreListView> {
  int? _busyStoreId;

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    final auth = context.read<AuthState>();
    // Store managers follow their store's results; they do not run inspections.
    final canInspect = auth.role != 'store_manager';
    // Without a connection, unfinished inspections saved on this device can
    // still be continued.
    final savedOnDevice =
        inspections.loadError != null ? inspections.localDrafts : const [];

    final children = <Widget>[
      if (savedOnDevice.isNotEmpty) ...[
        const SectionTitle('Saved on this device'),
        for (final draft in savedOnDevice)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _savedDraftCard(context, inspections, draft),
          ),
        const SizedBox(height: AppSpacing.md),
        if (inspections.stores.isNotEmpty) const SectionTitle('Stores'),
      ],
      for (final raw in inspections.stores)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _storeCard(
              context, inspections, raw as Map<String, dynamic>, auth.userId,
              canInspect: canInspect),
        ),
      if (inspections.stores.isEmpty &&
          inspections.listsLoaded &&
          savedOnDevice.isEmpty)
        const EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No stores yet',
          message: 'Stores you can inspect will appear here.',
        ),
    ];

    return RefreshIndicator(
      onRefresh: () => inspections.refreshAll(includeDashboard: auth.isAdmin),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
        children: children,
      ),
    );
  }

  Widget _savedDraftCard(BuildContext context, InspectionState inspections,
      Map<String, dynamic> draft) {
    final store = draft['store'] as Map<String, dynamic>;
    final busy = _busyStoreId == store['id'];
    return AppCard(
      child: Row(
        children: [
          const IconAvatar(icon: Icons.save_outlined, tone: Tone.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store['name'] as String,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('Unfinished - score ${draft['score'] ?? '-'}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (busy)
            const _Spinner()
          else
            FilledButton.icon(
              onPressed: _busyStoreId != null
                  ? null
                  : () => _open(
                      context,
                      store['id'] as int,
                      () => inspections.resumeInspection(draft['id'] as int),
                      'resume'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume'),
            ),
        ],
      ),
    );
  }

  Widget _storeCard(BuildContext context, InspectionState inspections,
      Map<String, dynamic> store, int? userId,
      {required bool canInspect}) {
    final theme = Theme.of(context);
    final template = inspections.templates.isEmpty
        ? null
        : inspections.templates.first as Map<String, dynamic>;
    final storeId = store['id'] as int;
    final busy = _busyStoreId == storeId;
    final open = inspections.openInspectionFor(storeId, userId);
    final latest = inspections.latestSubmittedFor(storeId);
    final templateId = template?['id'] as int?;
    final latestScore = latest?['score'] as num?;
    final when = parseApiTime(latest?['submitted_at'] ?? latest?['created_at']);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconAvatar(icon: Icons.storefront_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store['name'] as String,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${store['store_code']} - ${store['address']}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (latest != null) ...[
                const SizedBox(width: AppSpacing.md),
                ScoreRing(score: latestScore, size: 46),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (open != null)
                      const StatusPill(
                          label: 'In progress',
                          tone: Tone.info,
                          icon: Icons.edit_outlined),
                    if (latest != null) ...[
                      StatusPill(
                          label: latest['grade']?.toString() ?? 'Submitted',
                          tone: toneForGrade(latest['grade'] as String?)),
                      if (when != null)
                        Text(relativeDay(when),
                            style: theme.textTheme.bodySmall),
                    ] else if (open == null)
                      const StatusPill(label: 'No inspections yet'),
                  ],
                ),
              ),
              if (canInspect) ...[
                const SizedBox(width: AppSpacing.md),
                _controls(context, inspections,
                    storeId: storeId,
                    templateId: templateId,
                    open: open,
                    busy: busy),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    InspectionState inspections, {
    required int storeId,
    required int? templateId,
    required Map<String, dynamic>? open,
    required bool busy,
  }) {
    if (busy) return const _Spinner();
    if (open != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _busyStoreId != null
                ? null
                : () => _open(
                    context,
                    storeId,
                    () => inspections.resumeInspection(open['id'] as int),
                    'resume'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Resume'),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: templateId != null && _busyStoreId == null,
            onSelected: (_) => _open(
                context,
                storeId,
                () => inspections.startInspection(storeId, templateId!),
                'start'),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'new', child: Text('Start a new inspection')),
            ],
          ),
        ],
      );
    }
    return FilledButton.icon(
      onPressed: templateId == null || _busyStoreId != null
          ? null
          : () => _open(context, storeId,
              () => inspections.startInspection(storeId, templateId), 'start'),
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Start'),
    );
  }

  Future<void> _open(
    BuildContext context,
    int storeId,
    Future<void> Function() prepare,
    String verb,
  ) async {
    final inspections = context.read<InspectionState>();
    setState(() => _busyStoreId = storeId);
    try {
      await prepare();
      if (context.mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const InspectionScreen()));
        // Refresh so the store shows Resume/Start according to what happened.
        inspections.loadHistory().ignore();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not $verb inspection: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyStoreId = null);
    }
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
}
