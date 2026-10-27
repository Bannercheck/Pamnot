enum Priority { low, normal, high }

class SubTask {
  const SubTask({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  SubTask copyWith({String? title, bool? done}) =>
      SubTask(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};

  factory SubTask.fromJson(Map<String, Object?> j) => SubTask(
        id: j['id']! as String,
        title: (j['title'] as String?) ?? '',
        done: j['done'] == true,
      );
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.notes = '',
    this.done = false,
    this.completedAt,
    this.priority = Priority.normal,
    this.due,
    this.hasTime = false,
    this.remindAt,
    this.subtasks = const [],
    this.colorIndex = 3,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String notes;
  final bool done;
  final DateTime? completedAt;
  final Priority priority;

  /// The day the task is planned for. When [hasTime] is false only the date
  /// part matters.
  final DateTime? due;
  final bool hasTime;

  /// When set and in the future, a notification is scheduled.
  final DateTime? remindAt;
  final List<SubTask> subtasks;
  final int colorIndex;
  final DateTime createdAt;

  int get subtasksDone => subtasks.where((s) => s.done).length;

  TaskItem copyWith({
    String? title,
    String? notes,
    bool? done,
    DateTime? Function()? completedAt,
    Priority? priority,
    DateTime? Function()? due,
    bool? hasTime,
    DateTime? Function()? remindAt,
    List<SubTask>? subtasks,
    int? colorIndex,
  }) =>
      TaskItem(
        id: id,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        done: done ?? this.done,
        completedAt: completedAt != null ? completedAt() : this.completedAt,
        priority: priority ?? this.priority,
        due: due != null ? due() : this.due,
        hasTime: hasTime ?? this.hasTime,
        remindAt: remindAt != null ? remindAt() : this.remindAt,
        subtasks: subtasks ?? this.subtasks,
        colorIndex: colorIndex ?? this.colorIndex,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        if (notes.isNotEmpty) 'notes': notes,
        'done': done,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'priority': priority.name,
        if (due != null) 'due': due!.toIso8601String(),
        'hasTime': hasTime,
        if (remindAt != null) 'remindAt': remindAt!.toIso8601String(),
        if (subtasks.isNotEmpty) 'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'color': colorIndex,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TaskItem.fromJson(Map<String, Object?> j) => TaskItem(
        id: j['id']! as String,
        title: (j['title'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
        done: j['done'] == true,
        completedAt: _date(j['completedAt']),
        priority: Priority.values.firstWhere((p) => p.name == j['priority'],
            orElse: () => Priority.normal),
        due: _date(j['due']),
        hasTime: j['hasTime'] == true,
        remindAt: _date(j['remindAt']),
        subtasks: ((j['subtasks'] as List?) ?? const [])
            .map((s) => SubTask.fromJson((s as Map).cast<String, Object?>()))
            .toList(),
        colorIndex: (j['color'] as num?)?.toInt() ?? 3,
        createdAt: DateTime.parse(j['createdAt']! as String),
      );
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
