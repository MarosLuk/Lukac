import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reward_ledger.dart';
import '../state/providers.dart';
import 'ui/pill.dart';

class RewardBalanceCard extends ConsumerWidget {
  const RewardBalanceCard({super.key});

  static String _fmtCompact(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _fmtCountdown(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    two(int v) => v.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ledgerAsync = ref.watch(ledgerProvider);
    final ledger = ledgerAsync.valueOrNull ?? RewardLedger();
    final blockedAppsAsync = ref.watch(blockedAppsProvider);
    final blocked = blockedAppsAsync.valueOrNull ?? const <String>[];

    final balanceSeconds = ledger.balanceSeconds;
    final isLifted = ledger.isShieldLifted;
    final canSpendAny = balanceSeconds > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _fmtCompact(balanceSeconds),
            style: theme.textTheme.displayMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (isLifted)
                Pill(
                  icon: Icons.lock_open,
                  label:
                      'Unlocked · ${_fmtCountdown(ledger.remainingLift.inSeconds)}',
                  foreground: theme.colorScheme.primary,
                  border: theme.colorScheme.primary.withValues(alpha: 0.4),
                )
              else
                Pill(
                  icon: Icons.lock_outline,
                  label: blocked.isEmpty
                      ? 'No apps shielded'
                      : '${blocked.length} app${blocked.length == 1 ? '' : 's'} shielded',
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canSpendAny
                  ? () => _openUnlockSheet(context,
                      maxSeconds: balanceSeconds)
                  : null,
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: const Text('Unlock'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUnlockSheet(
    BuildContext context, {
    required int maxSeconds,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _UnlockSheet(maxSeconds: maxSeconds),
    );
  }
}

class _UnlockSheet extends ConsumerStatefulWidget {
  const _UnlockSheet({required this.maxSeconds});

  final int maxSeconds;

  @override
  ConsumerState<_UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends ConsumerState<_UnlockSheet> {
  // Stored in whole minutes; the ledger stores seconds but the UI is
  // minute-granular.
  int _minutes = 5;

  @override
  void initState() {
    super.initState();
    _minutes = _initialChoice(widget.maxSeconds);
  }

  /// Pick a sensible default: prefer 5 minutes when possible, otherwise use
  /// the full available balance (at least 1 minute).
  static int _initialChoice(int maxSeconds) {
    final maxMinutes = maxSeconds ~/ 60;
    if (maxMinutes >= 5) return 5;
    if (maxMinutes >= 1) return maxMinutes;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMinutes = (widget.maxSeconds ~/ 60).clamp(1, 240);
    // Show a compact set of common picks, filtered to what the user can
    // actually afford. We always include a "Custom" option via the slider.
    final presets = const [5, 10, 15, 30, 45, 60, 90, 120]
        .where((m) => m <= maxMinutes)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unlock apps for', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Spends minutes from your balance. Shield re-applies automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _formatMinutes(_minutes),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 4),
          Slider(
            value: _minutes.toDouble(),
            min: 1,
            max: maxMinutes.toDouble(),
            divisions: maxMinutes == 1 ? null : maxMinutes - 1,
            label: '$_minutes min',
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),
          if (presets.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in presets)
                  ChoiceChip(
                    label: Text('${m}m'),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final m = _minutes;
                await ref
                    .read(ledgerProvider.notifier)
                    .spend(Duration(minutes: m));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text('Unlock for $_minutes min'),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
