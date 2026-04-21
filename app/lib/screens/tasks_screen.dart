import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/task_tile.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  Future<void> _showAdd(BuildContext context) async {
    final state = AppStateScope.of(context);
    final titleCtrl = TextEditingController();
    int reward = 15;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New task',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Text('Reward: $reward minutes'),
                Slider(
                  value: reward.toDouble(),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  label: '$reward',
                  onChanged: (v) => setState(() => reward = v.round()),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    state.addTask(title, reward);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final tasks = state.tasks;
    return Scaffold(
      body: tasks.isEmpty
          ? const Center(child: Text('No tasks yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (_, i) {
                final t = tasks[i];
                return TaskTile(
                  task: t,
                  onComplete: () => state.completeTask(t.id),
                  onDelete: () => state.deleteTask(t.id),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAdd(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
