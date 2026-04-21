import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/external_task.dart';
import '../models/task.dart';
import '../state/providers.dart';
import '../widgets/task_tile.dart';
import '../widgets/ui/pill.dart';
import '../widgets/ui/section_header.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final externalAsync = ref.watch(externalTasksProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load tasks.\n\n$e'),
        ),
        data: (tasks) {
          final pending = tasks.where((t) => !t.completed).toList();
          final done = tasks.where((t) => t.completed).toList();
          final external = externalAsync.valueOrNull ?? const <ExternalTask>[];

          if (tasks.isEmpty && external.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No tasks yet.\nTap + to add one, or connect a source.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (external.isNotEmpty) ...[
                const SectionHeader('From sources'),
                for (final t in external)
                  _ExternalTaskTile(task: t),
              ],
              if (pending.isNotEmpty) ...[
                const SectionHeader('To do'),
                for (final t in pending) _buildRow(ref, t),
              ],
              if (done.isNotEmpty) ...[
                const SectionHeader('Completed'),
                for (final t in done) _buildRow(ref, t),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAdd(context),
        elevation: 1,
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }

  Widget _buildRow(WidgetRef ref, TaskItem t) {
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: Colors.red.withValues(alpha: 0.08),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) => ref.read(tasksProvider.notifier).delete(t.id),
      child: TaskTile(
        task: t,
        onComplete: () => ref.read(tasksProvider.notifier).complete(t.id),
      ),
    );
  }

  Future<void> _showAdd(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _AddTaskSheet(),
    );
  }
}

class _ExternalTaskTile extends ConsumerWidget {
  const _ExternalTaskTile({required this.task});

  final ExternalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dueAt = task.dueAt;
    final subtitle = dueAt == null
        ? 'No due date'
        : DateFormat.MMMd().add_jm().format(dueAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.title,
                        style: theme.textTheme.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Pill(label: task.sourceId),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => _showAcceptSheet(context, task),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }
}

Future<void> _showAcceptSheet(BuildContext context, ExternalTask task) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AcceptExternalSheet(task: task),
  );
}

class _AcceptExternalSheet extends ConsumerStatefulWidget {
  const _AcceptExternalSheet({required this.task});

  final ExternalTask task;

  @override
  ConsumerState<_AcceptExternalSheet> createState() =>
      _AcceptExternalSheetState();
}

class _AcceptExternalSheetState extends ConsumerState<_AcceptExternalSheet> {
  int _reward = 15;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('Accept task', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            widget.task.title,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Text(
            'Reward',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_reward min',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w400,
            ),
          ),
          Slider(
            value: _reward.toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            label: '$_reward',
            onChanged: (v) => setState(() => _reward = v.round()),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final task = widget.task;
                await ref
                    .read(tasksProvider.notifier)
                    .add(task.title, _reward);
                await ref
                    .read(externalTasksProvider.notifier)
                    .dismiss(task.sourceId, task.externalId);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Add to tasks'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTaskSheet extends ConsumerStatefulWidget {
  const _AddTaskSheet();

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  int _reward = 15;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('New task', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Finish chapter 3',
            ),
            autofocus: true,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 20),
          Text(
            'Reward',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_reward min',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w400,
            ),
          ),
          Slider(
            value: _reward.toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            label: '$_reward',
            onChanged: (v) => setState(() => _reward = v.round()),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final title = _titleCtrl.text.trim();
                if (title.isEmpty) return;
                await ref.read(tasksProvider.notifier).add(title, _reward);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Add task'),
            ),
          ),
        ],
      ),
    );
  }
}
