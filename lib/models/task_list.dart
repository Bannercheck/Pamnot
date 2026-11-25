import '../l10n/strings.dart';

/// The four boxes of the priority matrix.
enum Quadrant { doNow, plan, delegate, later }

/// A user list that groups tasks (Personal, Work, …).
class TaskList {
  const TaskList({
    required this.id,
    required this.name,
    this.colorIndex = 3,
    this.icon = 'list',
    this.order = 0,
    this.builtIn = false,
  });

  final String id;
  final String name;

  /// Key in `lib/ui/matrix/list_icons.dart`.
  final String icon;
  final int colorIndex;
  final int order;

  /// One of the ready-made lists from [defaults].
  final bool builtIn;

  static const personalId = 'personal';

  /// (id, colour, icon) of the ready-made lists, in display order.
  static const _builtIns = [
    (personalId, 3, 'person'),
    ('work', 4, 'work'),
    ('school', 5, 'school'),
    ('shopping', 1, 'shopping'),
    ('home', 2, 'home'),
  ];

  /// The five ready-made lists, named in Turkish when [tr], ordered 0..4.
  static List<TaskList> defaults({required bool tr}) {
    final s = tr ? S.tr : S.en;
    return [
      for (var i = 0; i < _builtIns.length; i++)
        TaskList(
          id: _builtIns[i].$1,
          name: s.defaultListName(_builtIns[i].$1),
          colorIndex: _builtIns[i].$2,
          icon: _builtIns[i].$3,
          order: i,
          builtIn: true,
        ),
    ];
  }

  TaskList copyWith({String? name, int? colorIndex, String? icon, int? order}) => TaskList(
        id: id,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        icon: icon ?? this.icon,
        order: order ?? this.order,
        builtIn: builtIn,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'color': colorIndex,
        'icon': icon,
        'order': order,
        'builtIn': builtIn,
      };

  factory TaskList.fromJson(Map<String, Object?> j) => TaskList(
        id: j['id']! as String,
        name: (j['name'] as String?) ?? '',
        colorIndex: (j['color'] as num?)?.toInt() ?? 3,
        icon: (j['icon'] as String?) ?? 'list',
        order: (j['order'] as num?)?.toInt() ?? 0,
        builtIn: j['builtIn'] == true,
      );
}
