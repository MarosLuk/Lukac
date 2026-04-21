import 'package:flutter/material.dart';

import '../state/app_state.dart';

class RewardBalanceCard extends StatelessWidget {
  const RewardBalanceCard({super.key});

  String _fmt(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final ledger = state.ledger;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reward balance', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              _fmt(ledger.balanceSeconds),
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 12),
            if (ledger.isShieldLifted)
              Row(
                children: [
                  Icon(Icons.lock_open, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Apps unlocked for ${_fmt(ledger.remainingLift.inSeconds)}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(Icons.lock, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Text(
                    state.blockedApps.isEmpty
                        ? 'No apps blocked yet'
                        : 'Blocked apps shielded',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final mins in const [5, 15, 30])
                  FilledButton.tonal(
                    onPressed: ledger.balanceSeconds >= 60
                        ? () =>
                            state.spendReward(Duration(minutes: mins))
                        : null,
                    child: Text('Spend ${mins}m'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
