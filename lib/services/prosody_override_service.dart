import 'dart:convert';

class ProsodyOverrideStore {
  const ProsodyOverrideStore({
    this.characters = const <String, ProsodyCharacterOverride>{},
  });

  final Map<String, ProsodyCharacterOverride> characters;

  bool get isEmpty => characters.isEmpty;
  bool get isNotEmpty => characters.isNotEmpty;

  ProsodyCharacterOverride? byPosition({
    required int lineNumber,
    required int charIndex,
    required String character,
  }) {
    final override = characters[positionKey(lineNumber, charIndex)];
    if (override == null || override.character != character) {
      return null;
    }
    return override;
  }

  ProsodyCharacterOverride? rhymeForLine({
    required int lineNumber,
    required String character,
  }) {
    for (final override in characters.values) {
      if (override.lineNumber == lineNumber &&
          override.character == character &&
          override.rhyme.trim().isNotEmpty) {
        return override;
      }
    }
    return null;
  }

  ProsodyOverrideStore put(ProsodyCharacterOverride override) {
    final next = Map<String, ProsodyCharacterOverride>.from(characters);
    if (override.tone.trim().isEmpty &&
        override.rhyme.trim().isEmpty &&
        override.note.trim().isEmpty) {
      next.remove(override.key);
    } else {
      next[override.key] = override;
    }
    return ProsodyOverrideStore(characters: Map.unmodifiable(next));
  }

  ProsodyOverrideStore putAll(Iterable<ProsodyCharacterOverride> overrides) {
    var store = this;
    for (final override in overrides) {
      store = store.put(override);
    }
    return store;
  }

  String toJsonText() {
    if (characters.isEmpty) {
      return '';
    }
    return jsonEncode({
      'version': 1,
      'characters': [
        for (final override in characters.values) override.toJson(),
      ],
    });
  }

  static ProsodyOverrideStore parse(String text) {
    final value = text.trim();
    if (value.isEmpty) {
      return const ProsodyOverrideStore();
    }
    try {
      final decoded = jsonDecode(value);
      Object? rawCharacters;
      if (decoded is Map<String, Object?>) {
        rawCharacters = decoded['characters'] ?? decoded['items'];
      } else if (decoded is Map) {
        rawCharacters = decoded['characters'] ?? decoded['items'];
      } else if (decoded is List) {
        rawCharacters = decoded;
      }
      if (rawCharacters is! List) {
        return const ProsodyOverrideStore();
      }
      final overrides = <String, ProsodyCharacterOverride>{};
      for (final item in rawCharacters) {
        final override = ProsodyCharacterOverride.fromJson(item);
        if (override == null) {
          continue;
        }
        overrides[override.key] = override;
      }
      return ProsodyOverrideStore(characters: Map.unmodifiable(overrides));
    } catch (_) {
      return const ProsodyOverrideStore();
    }
  }

  static String positionKey(int lineNumber, int charIndex) {
    return '$lineNumber:$charIndex';
  }
}

class ProsodyCharacterOverride {
  const ProsodyCharacterOverride({
    required this.lineNumber,
    required this.charIndex,
    required this.character,
    this.tone = '',
    this.rhyme = '',
    this.note = '',
  });

  final int lineNumber;
  final int charIndex;
  final String character;
  final String tone;
  final String rhyme;
  final String note;

  String get key => ProsodyOverrideStore.positionKey(lineNumber, charIndex);

  Map<String, Object?> toJson() {
    return {
      'line': lineNumber,
      'char_index': charIndex,
      'char': character,
      if (tone.trim().isNotEmpty) 'tone': tone.trim(),
      if (rhyme.trim().isNotEmpty) 'rhyme': rhyme.trim(),
      if (note.trim().isNotEmpty) 'note': note.trim(),
    };
  }

  ProsodyCharacterOverride copyWith({
    String? tone,
    String? rhyme,
    String? note,
  }) {
    return ProsodyCharacterOverride(
      lineNumber: lineNumber,
      charIndex: charIndex,
      character: character,
      tone: tone ?? this.tone,
      rhyme: rhyme ?? this.rhyme,
      note: note ?? this.note,
    );
  }

  static ProsodyCharacterOverride? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final lineNumber = _readInt(value['line'] ?? value['lineNumber'] ?? value['行']);
    final charIndex = _readInt(
      value['char_index'] ?? value['charIndex'] ?? value['index'] ?? value['字序'],
    );
    final character = (value['char'] ?? value['character'] ?? value['字'])
            ?.toString()
            .trim() ??
        '';
    if (lineNumber == null ||
        lineNumber < 1 ||
        charIndex == null ||
        charIndex < 1 ||
        character.isEmpty) {
      return null;
    }
    return ProsodyCharacterOverride(
      lineNumber: lineNumber,
      charIndex: charIndex,
      character: String.fromCharCode(character.runes.first),
      tone: _normalizeTone((value['tone'] ?? value['平仄'])?.toString() ?? ''),
      rhyme: (value['rhyme'] ?? value['rhyme_group'] ?? value['韵部'])
              ?.toString()
              .trim() ??
          '',
      note: (value['note'] ?? value['说明'])?.toString().trim() ?? '',
    );
  }
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

String _normalizeTone(String value) {
  final text = value.trim();
  if (text.contains('平')) {
    return '平';
  }
  if (text.contains('仄') ||
      text.contains('上') ||
      text.contains('去') ||
      text.contains('入')) {
    return '仄';
  }
  if (text == '多' || text.contains('多音')) {
    return '多';
  }
  if (text == '?' || text.contains('不确定')) {
    return '?';
  }
  return '';
}
