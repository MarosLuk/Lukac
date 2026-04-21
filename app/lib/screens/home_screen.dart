import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/reward_balance_card.dart';
import 'blocked_apps_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final pages = [
      _DashboardTab(),
      const TasksScreen(),
      const BlockedAppsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Rewards'),
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.block_outlined),
            selectedIcon: Icon(Icons.block),
            label: 'Blocked',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final pending = state.pendingTasks;
    return ListView(
      children: [
        const RewardBalanceCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Pending tasks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No pending tasks. Add one in the Tasks tab.'),
          )
        else
          for (final t in pending.take(5))
            ListTile(
              title: Text(t.title),
              subtitle: Text('+${t.rewardMinutes} min'),
              trailing: TextButton(
                onPressed: () => state.completeTask(t.id),
                child: const Text('Done'),
              ),
            ),
      ],
    );
  }
}
