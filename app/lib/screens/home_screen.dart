import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../widgets/reward_balance_card.dart';
import '../widgets/ui/section_header.dart';
import 'blocked_apps_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  static const _titles = <String>['Home', 'Tasks', 'Blocked', 'Settings'];

  @override
  Widget build(BuildContext context) {
    const pages = <Widget>[
      _DashboardTab(),
      TasksScreen(),
      BlockedAppsScreen(),
      SettingsScreen(),
    ];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        titleTextStyle: theme.textTheme.titleLarge,
      ),
      body: SafeArea(
        top: false,
        child: pages[_index],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.show_chart_outlined),
              selectedIcon: Icon(Icons.show_chart),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.check_circle_outline),
              selectedIcon: Icon(Icons.check_circle),
              label: 'Tasks',
            ),
            NavigationDestination(
              icon: Icon(Icons.block_outlined),
              selectedIcon: Icon(Icons.block),
              label: 'Blocked',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingTasksProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const RewardBalanceCard(),
        SectionHeader(
          'Pending tasks',
          trailing: Text(
            pending.isEmpty ? '' : '${pending.length}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (pending.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(
              'No pending tasks. Add one from the Tasks tab to start earning minutes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final t in pending.take(5))
            _PendingRow(
              title: t.title,
              rewardMinutes: t.rewardMinutes,
              onComplete: () =>
                  ref.read(tasksProvider.notifier).complete(t.id),
            ),
      ],
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.title,
    required this.rewardMinutes,
    required this.onComplete,
  });

  final String title;
  final int rewardMinutes;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(title, style: theme.textTheme.bodyLarge),
        subtitle: Text(
          '+$rewardMinutes min',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: TextButton(
          onPressed: onComplete,
          child: const Text('Done'),
        ),
      ),
    );
  }
}
