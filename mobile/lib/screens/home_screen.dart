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
      final inspections = context.read<InspectionState>();
      inspections.loadStores();
      inspections.loadTemplates();
      inspections.loadHistory();
      inspections.loadActions();
      if (context.read<AuthState>().isAdmin) inspections.loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
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
              onPressed: auth.logout,
              icon: const Icon(Icons.logout),
              tooltip: 'Log out')
        ],
      ),
      body: pages[_tab],
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
      onRefresh: inspections.loadActions,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: inspections.actions.length,
        itemBuilder: (context, index) {
          final action = inspections.actions[index] as Map<String, dynamic>;
          final store = action['store'] as Map<String, dynamic>;
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
                  '${store['name']} - ${action['severity']} - ${action['status']}'),
              trailing: _Pill(label: action['status'].toString()),
            ),
          );
        },
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
  int? _startingStoreId;

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: inspections.stores.length,
      itemBuilder: (context, index) {
        final store = inspections.stores[index] as Map<String, dynamic>;
        final template = inspections.templates.isEmpty
            ? null
            : inspections.templates.first as Map<String, dynamic>;
        final storeId = store['id'] as int;
        final starting = _startingStoreId == storeId;
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
            trailing: starting
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.icon(
                    onPressed: template == null || _startingStoreId != null
                        ? null
                        : () => _startInspection(
                              context,
                              inspections,
                              storeId,
                              template['id'] as int,
                            ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _startInspection(
    BuildContext context,
    InspectionState inspections,
    int storeId,
    int templateId,
  ) async {
    setState(() => _startingStoreId = storeId);
    try {
      await inspections.startInspection(storeId, templateId);
      if (context.mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const InspectionScreen()));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start inspection: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingStoreId = null);
    }
  }
}

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    return RefreshIndicator(
      onRefresh: inspections.loadHistory,
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
