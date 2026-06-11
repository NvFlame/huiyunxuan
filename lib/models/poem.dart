class Poem {
  const Poem({
    this.id,
    required this.identity,
    required this.collectionId,
    required this.title,
    required this.author,
    required this.dynasty,
    this.preface = '',
    required this.content,
    this.remark = '',
    this.translation = '',
    this.annotation = '',
    this.learningNote = '',
    this.appreciation = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String identity;
  final int collectionId;
  final String title;
  final String author;
  final String dynasty;
  final String preface;
  final String content;
  final String remark;
  final String translation;
  final String annotation;
  final String learningNote;
  final String appreciation;
  final DateTime createdAt;
  final DateTime updatedAt;

  Poem copyWith({
    int? id,
    String? identity,
    int? collectionId,
    String? title,
    String? author,
    String? dynasty,
    String? preface,
    String? content,
    String? remark,
    String? translation,
    String? annotation,
    String? learningNote,
    String? appreciation,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Poem(
      id: id ?? this.id,
      identity: identity ?? this.identity,
      collectionId: collectionId ?? this.collectionId,
      title: title ?? this.title,
      author: author ?? this.author,
      dynasty: dynasty ?? this.dynasty,
      preface: preface ?? this.preface,
      content: content ?? this.content,
      remark: remark ?? this.remark,
      translation: translation ?? this.translation,
      annotation: annotation ?? this.annotation,
      learningNote: learningNote ?? this.learningNote,
      appreciation: appreciation ?? this.appreciation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toElementMap({bool includeId = false}) {
    return {
      if (includeId && id != null) 'id': id,
      'identity': identity,
      'title': title,
      'author': author,
      'dynasty': dynasty,
      'preface': preface,
      'content': content,
      'remark': remark,
      'translation': translation,
      'annotation': annotation,
      'learning_note': learningNote,
      'appreciation': appreciation,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Poem.fromMap(Map<String, Object?> map) {
    return Poem(
      id: map['id'] as int?,
      identity: map['identity'] as String,
      collectionId: map['collection_id'] as int,
      title: map['title'] as String,
      author: map['author'] as String,
      dynasty: (map['dynasty'] as String?) ?? '',
      preface: (map['preface'] as String?) ?? '',
      content: map['content'] as String,
      remark: (map['remark'] as String?) ?? '',
      translation: (map['translation'] as String?) ?? '',
      annotation: (map['annotation'] as String?) ?? '',
      learningNote: (map['learning_note'] as String?) ?? '',
      appreciation: (map['appreciation'] as String?) ?? '',
      createdAt: _dateFromMap(map['created_at']),
      updatedAt: _dateFromMap(map['updated_at']),
    );
  }
}

DateTime _dateFromMap(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}
