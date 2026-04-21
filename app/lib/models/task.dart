import 'package:uuid/uuid.dart';

class TaskItem {
  TaskItem({
    String? id,
    required this.title,
    required this.rewardMinutes,
    this.completed = false,
    DateTime? createdAt,
    this.completedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String title;
  final int rewardMinutes;
  final bool completed;
  final DateTime createdAt;
  final DateTime? completedAt;

  TaskItem copyWith({bool? completed, DateTime? completedAt}) => TaskItem(
        id: id,
        title: title,
        rewardMinutes: rewardMinutes,
        completed: completed ?? this.completed,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'rewardMinutes': rewardMinutes,
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
        id: json['id'] as String,
        title: json['title'] as String,
        rewardMinutes: json['rewardMinutes'] as int,
        completed: json['completed'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String),
      );
}
