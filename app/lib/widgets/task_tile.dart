import 'package:flutter/material.dart';

import '../models/task.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onComplete,
    required this.onDelete,
  });

  final TaskItem task;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: task.completed,
        onChanged: task.completed ? null : (_) => onComplete(),
      ),
      title: Text(
        task.title,
        style: TextStyle(
          decoration:
              task.completed ? TextDecoration.lineThrough : TextDecoration.none,
        ),
      ),
      subtitle: Text('+${task.rewardMinutes} min'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}
