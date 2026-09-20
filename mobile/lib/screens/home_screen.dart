import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';
import '../inspections/inspection_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/content_width.dart';
import 'actions_view.dart';
import 'dashboard_view.dart';
import 'history_view.dart';
import 'stores_view.dart';

export 'actions_view.dart' show ActionsView;
export 'dashboard_view.dart' show DashboardView;
export 'history_view.dart' show HistoryView;
export 'stores_view.dart' show StoreListView;

class _TabSpec {
  const _TabSpec(this.title, this.icon, this.selectedIcon, this.page);

  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

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
    final tabs = [
      const _TabSpec('Stores', Icons.storefront_outlined, Icons.storefront,
          StoreListView()),
      const _TabSpec(
          'History', Icons.history_outlined, Icons.history, HistoryView()),
      const _TabSpec(
          'Actions', Icons.task_alt_outlined, Icons.task_alt, ActionsView()),
      if (auth.isAdmin)
        const _TabSpec('Dashboard', Icons.dashboard_outlined, Icons.dashboard,
            DashboardView()),
    ];
    final current = tabs[_tab.clamp(0, tabs.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          _AccountMenu(user: auth.user, onLogout: _logout),
          const SizedBox(width: AppSpacing.sm),
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
          Expanded(child: ContentWidth(child: current.page)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSoft)),
        ),
        // Tabs stay as wide as the content on big screens instead of spreading
        // to the window edges.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: NavigationBar(
              selectedIndex: _tab.clamp(0, tabs.length - 1),
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.title,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The signed-in user: initials in the app bar, details and Log out in a menu.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.user, required this.onLogout});

  final Map<String, dynamic>? user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user?['name']?.toString();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      onSelected: (value) {
        if (value == 'logout') onLogout();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name ?? 'Signed in', style: theme.textTheme.titleSmall),
              if (user?['email'] != null)
                Text(user!['email'].toString(),
                    style: theme.textTheme.bodySmall),
              if (roleLabel(user?['role'] as String?).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(roleLabel(user?['role'] as String?),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.primary)),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 20),
              SizedBox(width: 12),
              Text('Log out'),
            ],
          ),
        ),
      ],
      child: CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.primarySoft,
        child: Text(initials(name),
            style: theme.textTheme.labelLarge
                ?.copyWith(color: AppColors.primaryDark)),
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
    final colors = toneColors(Tone.danger);
    return Material(
      color: colors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 20, color: colors.foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.foreground)),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: colors.foreground),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
