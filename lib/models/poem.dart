class Poem {
  const Poem({
    this.id,
    required this.collectionId,
    required this.title,
    required this.author,
    required this.dynasty,
    required this.content,
    this.remark = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int collectionId;
  final String title;
  final String author;
  final String dynasty;
  final String content;
  final String remark;
  final DateTime createdAt;
  final DateTime updatedAt;

  Poem copyWith({
    int? id,
    int? collectionId,
    String? title,
    String? author,
    String? dynasty,
    String? content,
    String? remark,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Poem(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      title: title ?? this.title,
      author: author ?? this.author,
      dynasty: dynasty ?? this.dynasty,
      content: content ?? this.content,
      remark: remark ?? this.remark,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'collection_id': collectionId,
      'title': title,
      'author': author,
      'dynasty': dynasty,
      'content': content,
      'remark': remark,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Poem.fromMap(Map<String, Object?> map) {
    return Poem(
      id: map['id'] as int?,
      collectionId: map['collection_id'] as int,
      title: map['title'] as String,
      author: map['author'] as String,
      dynasty: (map['dynasty'] as String?) ?? '',
      content: map['content'] as String,
      remark: (map['remark'] as String?) ?? '',
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
