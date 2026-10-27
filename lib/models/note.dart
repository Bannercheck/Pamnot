import 'ink.dart';

class Note {
  const Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.ink = const [],
    this.colorIndex = 0,
    this.pinned = false,
    this.paper = PaperStyle.lined,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final List<InkStroke> ink;

  /// Index into the soft note palette.
  final int colorIndex;
  final bool pinned;
  final PaperStyle paper;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty && ink.isEmpty;
  bool get hasInk => ink.isNotEmpty;

  Note copyWith({
    String? title,
    String? body,
    List<InkStroke>? ink,
    int? colorIndex,
    bool? pinned,
    PaperStyle? paper,
    List<String>? tags,
    DateTime? updatedAt,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        ink: ink ?? this.ink,
        colorIndex: colorIndex ?? this.colorIndex,
        pinned: pinned ?? this.pinned,
        paper: paper ?? this.paper,
        tags: tags ?? this.tags,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        // Ink lives in its own document (see AppController), not in here.
        if (ink.isNotEmpty) 'hasInk': true,
        'color': colorIndex,
        'pinned': pinned,
        'paper': paper.name,
        if (tags.isNotEmpty) 'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, Object?> j) => Note(
        id: j['id']! as String,
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        colorIndex: (j['color'] as num?)?.toInt() ?? 0,
        pinned: j['pinned'] == true,
        paper: PaperStyle.values.firstWhere((p) => p.name == j['paper'],
            orElse: () => PaperStyle.lined),
        tags: ((j['tags'] as List?) ?? const []).cast<String>(),
        createdAt: DateTime.parse(j['createdAt']! as String),
        updatedAt: DateTime.parse(j['updatedAt']! as String),
      );
}
