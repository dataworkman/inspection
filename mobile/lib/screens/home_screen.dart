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
        title: const Text('Inspections'),
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
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: inspections.actions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final action = inspections.actions[index] as Map<String, dynamic>;
          final store = action['store'] as Map<String, dynamic>;
          return ListTile(
            title: Text(action['title'] as String),
            subtitle: Text(
                '${store['name']} - ${action['severity']} - ${action['status']}'),
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: inspections.stores.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final store = inspections.stores[index] as Map<String, dynamic>;
        final template = inspections.templates.isEmpty
            ? null
            : inspections.templates.first as Map<String, dynamic>;
        final storeId = store['id'] as int;
        final starting = _startingStoreId == storeId;
        return ListTile(
          title: Text(store['name'] as String),
          subtitle: Text('${store['store_code']} - ${store['address']}'),
          trailing: starting
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          enabled: template != null && _startingStoreId == null,
          onTap: () async {
            setState(() => _startingStoreId = storeId);
            try {
              await inspections.startInspection(
                  storeId, template!['id'] as int);
              if (context.mounted) {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const InspectionScreen()));
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
          },
        );
      },
    );
  }
}

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final inspections = context.watch<InspectionState>();
    return RefreshIndicator(
      onRefresh: inspections.loadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: inspections.history.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = inspections.history[index] as Map<String, dynamic>;
          final store = item['store'] as Map<String, dynamic>;
          return ListTile(
            title: Text(store['name'] as String),
            subtitle: Text('${item['status']} - score ${item['score'] ?? '-'}'),
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
      padding: const EdgeInsets.all(16),
      children: [
        Text(
            'Average score: ${dashboard['average_inspection_score'] ?? dashboard['average_score'] ?? '-'}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Submitted inspections: ${dashboard['submitted_inspections']}'),
        Text('Open actions: ${dashboard['open_corrective_actions'] ?? 0}'),
        Text(
            'Critical actions: ${dashboard['critical_corrective_actions'] ?? 0}'),
        const SizedBox(height: 16),
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
    return ListTile(
      title: Text(store['name'] as String),
      subtitle: Text(
          'Latest ${latestScore ?? '-'} / Avg ${averageScore ?? '-'} across $submittedCount submitted - $openIssues open actions'),
    );
  }
}
