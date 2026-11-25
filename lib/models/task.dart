import 'task_list.dart';

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
    this.listId = TaskList.personalId,
    this.quadrant = Quadrant.plan,
    this.order = 0,
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

  /// The [TaskList] this task belongs to.
  final String listId;

  /// The matrix box this task sits in.
  final Quadrant quadrant;

  /// Position inside its box.
  final int order;

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
    String? listId,
    Quadrant? quadrant,
    int? order,
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
        listId: listId ?? this.listId,
        quadrant: quadrant ?? this.quadrant,
        order: order ?? this.order,
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
        'list': listId,
        'quadrant': quadrant.name,
        'order': order,
      };

  factory TaskItem.fromJson(Map<String, Object?> j) {
    final priority =
        Priority.values.firstWhere((p) => p.name == j['priority'], orElse: () => Priority.normal);
    return TaskItem(
        id: j['id']! as String,
        title: (j['title'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
        done: j['done'] == true,
        completedAt: _date(j['completedAt']),
        priority: priority,
        due: _date(j['due']),
        hasTime: j['hasTime'] == true,
        remindAt: _date(j['remindAt']),
        subtasks: ((j['subtasks'] as List?) ?? const [])
            .map((s) => SubTask.fromJson((s as Map).cast<String, Object?>()))
            .toList(),
        colorIndex: (j['color'] as num?)?.toInt() ?? 3,
        createdAt: DateTime.parse(j['createdAt']! as String),
        // Tasks saved before lists existed go to Personal; high priority ones
        // to the "do now" box, everything else to "plan".
        listId: (j['list'] as String?) ?? TaskList.personalId,
        quadrant: Quadrant.values.firstWhere((q) => q.name == j['quadrant'],
            orElse: () => priority == Priority.high ? Quadrant.doNow : Quadrant.plan),
        order: (j['order'] as num?)?.toInt() ?? 0,
      );
  }
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
