import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';
import '../inspections/inspection_state.dart';
import 'inspection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<InspectionState>()
          .refreshAll(includeDashboard: context.read<AuthState>().isAdmin);
    });
  }

  Future<void> _logout() async {
    final inspections = context.read<InspectionState>();
    final auth = context.read<AuthState>();
    if (inspections.hasPendingSaves) {
      // Try to send what is still waiting; only ask when that does not work.
      try {
        await inspections
            .flushPendingSaves()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (inspections.hasPendingSaves) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Unsent changes'),
            content: const Text(
                'Some of your changes could not be sent and will be lost if you log out.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Log out anyway'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final inspections = context.watch<InspectionState>();
    final pages = [
      const StoreListView(),
      const HistoryView(),
      const ActionsView(),
      if (auth.isAdmin) const DashboardView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Inspections'),
        actions: [
          IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              tooltip: 'Log out')
        ],
      ),
      body: Column(
        children: [
          if (inspections.loadError != null)
            _ConnectionBanner(
              message: inspections.loadError!,
              onRetry: () =>
                  inspections.refreshAll(includeDashboard: auth.isAdmin),
            ),
          Expanded(child: pages[_tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.storefront), label: 'Stores'),
          const NavigationDestination(
              icon: Icon(Icons.history), label: 'History'),
          const NavigationDestination(
              icon: Icon(Icons.task_alt), label: 'Actions'),
          if (auth.isAdmin)
            const NavigationDestination(
                icon: Icon(Icons.dashboard), label: 'Dashboard'),
        ],
      ),
    );
  }
}

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
              padding: const EdgeInsets.all(32),
              children: const [
                Center(child: Text('No corrective actions')),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: inspections.actions.length,
              itemBuilder: (context, index) {
                final action =
                    inspections.actions[index] as Map<String, dynamic>;
                final store = action['store'] as Map<String, dynamic>;
                final due = action['due_date'];
                return _ContentCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _StatusIcon(
                      icon: Icons.report_problem,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    title: Text(action['title'] as String,
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Text(
                        '${store['name']} - ${action['severity']}${due == null ? '' : ' - due $due'}'),
                    trailing: _Pill(label: action['status'].toString()),
                    onTap: () => _showActionSheet(context, action),
                  ),
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
    final assignee = action['assigned_to'] as Map<String, dynamic>?;
    final description = action['description']?.toString() ?? '';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(action['title'] as String,
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text([
                (action['store'] as Map<String, dynamic>)['name'],
                action['severity'],
                if (action['due_date'] != null) 'due ${action['due_date']}',
                if (assignee != null) 'assigned to ${assignee['name']}',
              ].join(' - ')),
              if (description.isNotEmpty && description != action['title']) ...[
                const SizedBox(height: 8),
                Text(description),
              ],
              const Divider(height: 24),
              Text('Set status',
                  style: Theme.of(sheetContext).textTheme.titleSmall),
              for (final status in allowed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(status),
                  trailing: status == current ? const Icon(Icons.check) : null,
                  onTap: status == current
                      ? null
                      : () async {
                          Navigator.of(sheetContext).pop();
                          try {
                            await inspections.updateActionStatus(
                                action['id'] as int, status);
                          } catch (error) {
                            messenger.showSnackBar(SnackBar(
                                content: Text(
                                    'Could not update the action: $error')));
                          }
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final userId = auth.userId;
    // Store managers follow their store's results; they do not run inspections.
    final canInspect = auth.role != 'store_manager';
    // Without a connection, unfinished inspections saved on this device can
    // still be continued.
    final savedOnDevice =
        inspections.loadError != null ? inspections.localDrafts : const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (savedOnDevice.isNotEmpty) ...[
          Text('Saved on this device',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final draft in savedOnDevice)
            _savedDraftCard(context, inspections, draft),
          const SizedBox(height: 12),
        ],
        for (final raw in inspections.stores)
          _storeCard(context, inspections, raw as Map<String, dynamic>, userId,
              canInspect: canInspect),
      ],
    );
  }

  Widget _savedDraftCard(BuildContext context, InspectionState inspections,
      Map<String, dynamic> draft) {
    final store = draft['store'] as Map<String, dynamic>;
    final busy = _busyStoreId == store['id'];
    return _ContentCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _StatusIcon(
          icon: Icons.save,
          color: Theme.of(context).colorScheme.secondary,
        ),
        title: Text(store['name'] as String,
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text('Unfinished - score ${draft['score'] ?? '-'}'),
        trailing: busy
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.icon(
                onPressed: _busyStoreId != null
                    ? null
                    : () => _open(
                        context,
                        store['id'] as int,
                        () => inspections.resumeInspection(draft['id'] as int),
                        'resume'),
                icon: const Icon(Icons.play_circle),
                label: const Text('Resume'),
              ),
      ),
    );
  }

  Widget _storeCard(BuildContext context, InspectionState inspections,
      Map<String, dynamic> store, int? userId,
      {required bool canInspect}) {
    final template = inspections.templates.isEmpty
        ? null
        : inspections.templates.first as Map<String, dynamic>;
    final storeId = store['id'] as int;
    final busy = _busyStoreId == storeId;
    final open = inspections.openInspectionFor(storeId, userId);
    final templateId = template?['id'] as int?;
    return _ContentCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _StatusIcon(
          icon: Icons.storefront,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(store['name'] as String,
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${store['store_code']} - ${store['address']}'),
        ),
        trailing: !canInspect
            ? null
            : busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (open != null) ...[
                        FilledButton.icon(
                          onPressed: _busyStoreId != null
                              ? null
                              : () => _open(
                                  context,
                                  storeId,
                                  () => inspections
                                      .resumeInspection(open['id'] as int),
                                  'resume'),
                          icon: const Icon(Icons.play_circle),
                          label: const Text('Resume'),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'More',
                          enabled: templateId != null && _busyStoreId == null,
                          onSelected: (_) => _open(
                              context,
                              storeId,
                              () => inspections.startInspection(
                                  storeId, templateId!),
                              'start'),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'new',
                                child: Text('Start a new inspection')),
                          ],
                        ),
                      ] else
                        FilledButton.icon(
                          onPressed: templateId == null || _busyStoreId != null
                              ? null
                              : () => _open(
                                  context,
                                  storeId,
                                  () => inspections.startInspection(
                                      storeId, templateId),
                                  'start'),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start'),
                        ),
                    ],
                  ),
      ),
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

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    return RefreshIndicator(
      onRefresh: () => inspections.refreshAll(
          includeDashboard: context.read<AuthState>().isAdmin),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: inspections.history.length,
        itemBuilder: (context, index) {
          final item = inspections.history[index] as Map<String, dynamic>;
          final store = item['store'] as Map<String, dynamic>;
          return _ContentCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _StatusIcon(
                icon: Icons.assignment_turned_in,
                color: Theme.of(context).colorScheme.secondary,
              ),
              title: Text(store['name'] as String,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle:
                  Text('${item['status']} - score ${item['score'] ?? '-'}'),
              trailing: _Pill(label: item['grade']?.toString() ?? 'Open'),
              onTap: () async {
                try {
                  final inspector = item['inspector'] as Map<String, dynamic>?;
                  final resumable =
                      InspectionState.openStatuses.contains(item['status']) &&
                          inspector?['id'] == context.read<AuthState>().userId;
                  if (resumable) {
                    await inspections.resumeInspection(item['id'] as int);
                    if (context.mounted) {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const InspectionScreen()));
                      inspections.loadHistory().ignore();
                    }
                    return;
                  }
                  final detail =
                      await inspections.loadInspectionDetail(item['id'] as int);
                  if (context.mounted) {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            InspectionResultScreen(inspection: detail)));
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Could not open inspection: $error')),
                    );
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<InspectionState>().dashboard;
    if (dashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final storeRows = (dashboard['store_ranking'] ??
        dashboard['stores'] ??
        const []) as List<dynamic>;
    final attentionRows =
        (dashboard['attention_required'] ?? const []) as List<dynamic>;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Average score',
              value:
                  '${dashboard['average_inspection_score'] ?? dashboard['average_score'] ?? '-'}',
              icon: Icons.speed,
            ),
            _MetricCard(
              label: 'Submitted',
              value: '${dashboard['submitted_inspections'] ?? 0}',
              icon: Icons.assignment_turned_in,
            ),
            _MetricCard(
              label: 'Open actions',
              value: '${dashboard['open_corrective_actions'] ?? 0}',
              icon: Icons.task_alt,
            ),
            _MetricCard(
              label: 'Critical',
              value: '${dashboard['critical_corrective_actions'] ?? 0}',
              icon: Icons.priority_high,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (attentionRows.isNotEmpty) ...[
          Text('Attention required',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final raw in attentionRows)
            _DashboardStoreTile(row: raw as Map<String, dynamic>),
          const SizedBox(height: 16),
        ],
        Text('Store ranking', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final raw in storeRows)
          _DashboardStoreTile(row: raw as Map<String, dynamic>),
      ],
    );
  }
}

class _DashboardStoreTile extends StatelessWidget {
  const _DashboardStoreTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final store = row['store'] as Map<String, dynamic>;
    final latestScore = row['latest_score'];
    final averageScore = row['average_score'];
    final submittedCount = row['submitted_inspections'] ?? 0;
    final openIssues = row['open_issues'] ?? 0;
    return _ContentCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(store['name'] as String),
        subtitle: Text(
            'Latest ${latestScore ?? '-'} / Avg ${averageScore ?? '-'} across $submittedCount submitted - $openIssues open actions'),
        trailing: _Pill(label: '$openIssues open'),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: child,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusIcon(
                  icon: icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
