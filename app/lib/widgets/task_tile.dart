import 'package:flutter/material.dart';

import '../models/task.dart';

/// Minimal task row: soft left-hand circular checkbox with an animated tick,
/// tight typography, and a muted reward chip on the right.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onComplete,
  });

  final TaskItem task;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = task.completed;
    return InkWell(
      onTap: done ? null : onComplete,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            _AnimatedCheck(checked: done),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                task.title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: done
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                  decoration: done
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _RewardChip(minutes: task.rewardMinutes, muted: done),
          ],
        ),
      ),
    );
  }
}

class _AnimatedCheck extends StatelessWidget {
  const _AnimatedCheck({required this.checked});
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: checked ? cs.primary : cs.outlineVariant,
          width: 1.5,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: checked
            ? Icon(
                Icons.check,
                size: 14,
                color: cs.onPrimary,
                key: const ValueKey('check'),
              )
            : const SizedBox.shrink(key: ValueKey('empty')),
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.minutes, required this.muted});

  final int minutes;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = muted ? cs.onSurfaceVariant : cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: muted
              ? cs.outlineVariant
              : cs.primary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        '+${minutes}m',
        style: theme.textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
