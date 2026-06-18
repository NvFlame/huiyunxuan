import '../models/poem.dart';
import 'rhyme_service.dart';

class RegulatedVerseCheck {
  const RegulatedVerseCheck({
    required this.applicable,
    required this.unresolved,
    required this.formLabel,
    required this.displayForm,
    required this.ok,
    required this.summary,
    required this.lines,
    required this.relations,
    required this.unresolvedPositions,
  });

  final bool applicable;
  final bool unresolved;
  final String formLabel;
  final String displayForm;
  final bool ok;
  final String summary;
  final List<RegulatedVerseLineCheck> lines;
  final List<RegulatedVerseRelationCheck> relations;
  final List<RegulatedVerseUnresolvedTone> unresolvedPositions;

  bool get hasProblems {
    return lines.any((line) => line.hasRed) ||
        relations.any((relation) => relation.color == ProsodyCheckColor.red);
  }
}

class RegulatedVerseLineCheck {
  const RegulatedVerseLineCheck({
    required this.lineNumber,
    required this.pattern,
    required this.status,
    required this.tags,
    required this.marks,
  });

  final int lineNumber;
  final String pattern;
  final ProsodyLineStatus status;
  final List<String> tags;
  final List<RegulatedVerseMark> marks;

  bool get hasRed => marks.any((mark) => mark.color == ProsodyCheckColor.red);
}

class RegulatedVerseRelationCheck {
  const RegulatedVerseRelationCheck({
    required this.firstLine,
    required this.secondLine,
    required this.tag,
    required this.color,
  });

  final int firstLine;
  final int secondLine;
  final String tag;
  final ProsodyCheckColor color;
}

class RegulatedVerseMark {
  const RegulatedVerseMark({
    required this.start,
    required this.end,
    required this.color,
    required this.label,
  });

  final int start;
  final int end;
  final ProsodyCheckColor color;
  final String label;
}

class RegulatedVerseUnresolvedTone {
  const RegulatedVerseUnresolvedTone({
    required this.lineNumber,
    required this.charIndex,
    required this.character,
    required this.mark,
  });

  final int lineNumber;
  final int charIndex;
  final String character;
  final String mark;
}

enum ProsodyCheckColor { green, red }

enum ProsodyLineStatus { ok, error }

RegulatedVerseCheck checkRegulatedVerse(Poem poem) {
  if (!poem.prosodySupported ||
      !poem.prosodyEnabled ||
      poem.prosodySystem != Poem.prosodySystemRegulatedVerse) {
    return const RegulatedVerseCheck(
      applicable: false,
      unresolved: false,
      formLabel: '',
      displayForm: '',
      ok: false,
      summary: '当前作品暂不进行近体诗格律审查。',
      lines: <RegulatedVerseLineCheck>[],
      relations: <RegulatedVerseRelationCheck>[],
      unresolvedPositions: <RegulatedVerseUnresolvedTone>[],
    );
  }

  final toneLines = analyzeCharacterTones(poem);
  final formLabel = _detectForm(toneLines) ?? poem.prosodyForm.trim();
  if (toneLines.isEmpty ||
      formLabel.isEmpty ||
      toneLines.any((line) => line.characters.isEmpty)) {
    return RegulatedVerseCheck(
      applicable: true,
      unresolved: true,
      formLabel: formLabel,
      displayForm: formLabel.isEmpty ? '候选' : '$formLabel候选',
      ok: false,
      summary: '正文结构尚不能进行近体诗格律审查。',
      lines: const <RegulatedVerseLineCheck>[],
      relations: const <RegulatedVerseRelationCheck>[],
      unresolvedPositions: const <RegulatedVerseUnresolvedTone>[],
    );
  }

  final unresolvedPositions = <RegulatedVerseUnresolvedTone>[];
  final patterns = <String>[];
  for (final line in toneLines) {
    final buffer = StringBuffer();
    for (var index = 0; index < line.characters.length; index += 1) {
      final tone = line.characters[index];
      if (tone.mark != '平' && tone.mark != '仄') {
        unresolvedPositions.add(
          RegulatedVerseUnresolvedTone(
            lineNumber: line.lineNumber,
            charIndex: index + 1,
            character: tone.character,
            mark: tone.mark,
          ),
        );
      }
      buffer.write(tone.mark);
    }
    patterns.add(buffer.toString());
  }

  if (unresolvedPositions.isNotEmpty) {
    return RegulatedVerseCheck(
      applicable: true,
      unresolved: true,
      formLabel: formLabel,
      displayForm: formLabel.isEmpty ? '候选' : '$formLabel候选',
      ok: false,
      summary: '仍有多音或未知字未确认，暂只显示逐字平仄。',
      lines: const <RegulatedVerseLineCheck>[],
      relations: const <RegulatedVerseRelationCheck>[],
      unresolvedPositions: List.unmodifiable(unresolvedPositions),
    );
  }

  if (patterns.any((pattern) => pattern.length != 5 && pattern.length != 7) ||
      patterns.map((pattern) => pattern.length).toSet().length != 1) {
    return RegulatedVerseCheck(
      applicable: true,
      unresolved: false,
      formLabel: formLabel,
      displayForm: '非正格',
      ok: false,
      summary: '正文句长不一致，不能按五七言近体正格审查。如有需求，建议和智能体讨论本诗格律情况。',
      lines: const <RegulatedVerseLineCheck>[],
      relations: const <RegulatedVerseRelationCheck>[],
      unresolvedPositions: const <RegulatedVerseUnresolvedTone>[],
    );
  }

  final lineChecks = [
    for (var i = 0; i < patterns.length; i += 1)
      _analyzeLine(i + 1, patterns[i]),
  ];
  _applyCoupletRescue(lineChecks);
  final relations = _analyzeRelations(lineChecks);
  final ok = !lineChecks.any((line) => line.hasRed) &&
      !relations.any((relation) => relation.color == ProsodyCheckColor.red);
  final firstLineCategory = _categoryOf(patterns.first);

  return RegulatedVerseCheck(
    applicable: true,
    unresolved: false,
    formLabel: formLabel,
    displayForm: ok ? formLabel : '非正格',
    ok: ok,
    summary: ok
        ? '格律审查通过，$firstLineCategory。'
        : '检测到非正格。如有需求，建议和智能体讨论本诗格律情况。',
    lines: List.unmodifiable(lineChecks),
    relations: List.unmodifiable(relations),
    unresolvedPositions: const <RegulatedVerseUnresolvedTone>[],
  );
}

String? _detectForm(List<ToneLine> lines) {
  if (lines.length != 4 && lines.length != 8) {
    return null;
  }
  final lengths = lines.map((line) => line.characters.length).toSet();
  if (lengths.length != 1) {
    return null;
  }
  final length = lengths.first;
  if (length != 5 && length != 7) {
    return null;
  }
  if (lines.length == 4 && length == 5) return '五绝';
  if (lines.length == 8 && length == 5) return '五律';
  if (lines.length == 4 && length == 7) return '七绝';
  if (lines.length == 8 && length == 7) return '七律';
  return null;
}

String _categoryOf(String pattern) {
  final second = pattern[1];
  final last = pattern[pattern.length - 1];
  if (second == '仄' && last == '平') return '仄起平收';
  if (second == '仄' && last == '仄') return '仄起仄收';
  if (second == '平' && last == '平') return '平起平收';
  return '平起仄收';
}

String _coreOf(String pattern) {
  if (pattern.length == 5) {
    return pattern;
  }
  return pattern.substring(2);
}

String _expectedCoreCategory(String pattern) {
  if (pattern.length == 5) {
    return _categoryOf(pattern);
  }
  switch (_categoryOf(pattern)) {
    case '平起平收':
      return '仄起平收';
    case '平起仄收':
      return '仄起仄收';
    case '仄起平收':
      return '平起平收';
    default:
      return '平起仄收';
  }
}

int _offsetOf(String pattern) => pattern.length == 5 ? 0 : 2;

RegulatedVerseLineCheck _ok(
  int lineNumber,
  String pattern,
  String tag,
) {
  return RegulatedVerseLineCheck(
    lineNumber: lineNumber,
    pattern: pattern,
    status: ProsodyLineStatus.ok,
    tags: <String>[tag],
    marks: <RegulatedVerseMark>[
      RegulatedVerseMark(
        start: 1,
        end: pattern.length,
        color: ProsodyCheckColor.green,
        label: tag,
      ),
    ],
  );
}

RegulatedVerseLineCheck _err(
  int lineNumber,
  String pattern,
  String tag,
) {
  return RegulatedVerseLineCheck(
    lineNumber: lineNumber,
    pattern: pattern,
    status: ProsodyLineStatus.error,
    tags: <String>[tag],
    marks: <RegulatedVerseMark>[
      RegulatedVerseMark(
        start: 1,
        end: pattern.length,
        color: ProsodyCheckColor.red,
        label: tag,
      ),
    ],
  );
}

RegulatedVerseLineCheck _threeFlatTail(int lineNumber, String pattern) {
  final offset = _offsetOf(pattern);
  return RegulatedVerseLineCheck(
    lineNumber: lineNumber,
    pattern: pattern,
    status: ProsodyLineStatus.error,
    tags: const <String>['三平尾'],
    marks: <RegulatedVerseMark>[
      RegulatedVerseMark(
        start: offset + 3,
        end: offset + 5,
        color: ProsodyCheckColor.red,
        label: '三平尾',
      ),
    ],
  );
}

RegulatedVerseLineCheck _analyzeLine(int lineNumber, String pattern) {
  final core = _coreOf(pattern);
  final expectedCategory = _expectedCoreCategory(pattern);
  if (lineNumber.isEven && pattern.endsWith('仄')) {
    return _err(lineNumber, pattern, '错脚');
  }
  if (core.substring(2) == '平平平') {
    return _threeFlatTail(lineNumber, pattern);
  }
  if (_categoryOf(core) != expectedCategory) {
    return _err(lineNumber, pattern, '失律');
  }

  switch (expectedCategory) {
    case '仄起平收':
      if (core == '仄仄仄平平' || core == '平仄仄平平') {
        return _ok(lineNumber, pattern, '合律');
      }
      return _fallback(lineNumber, pattern, core);
    case '平起平收':
      if (core == '平平仄仄平') return _ok(lineNumber, pattern, '合律');
      if (core == '仄平仄仄平') return _err(lineNumber, pattern, '孤平');
      if (core == '仄平平仄平') return _ok(lineNumber, pattern, '自救');
      if (core == '平平平仄平') return _ok(lineNumber, pattern, '合律');
      return _fallback(lineNumber, pattern, core);
    case '仄起仄收':
      if (core == '仄仄平平仄' || core == '平仄平平仄') {
        return _ok(lineNumber, pattern, '合律');
      }
      if (core == '仄仄仄平仄' || core == '平仄仄平仄') {
        return _ok(lineNumber, pattern, '半拗');
      }
      if (core == '仄仄仄仄仄' || core == '仄仄平仄仄') {
        return _err(lineNumber, pattern, '拗句');
      }
      return _fallback(lineNumber, pattern, core);
    default:
      if (core == '平平平仄仄' || core == '仄平平仄仄') {
        return _ok(lineNumber, pattern, '合律');
      }
      if (core == '平平仄仄仄') return _ok(lineNumber, pattern, '三仄尾');
      if (core == '平平仄平仄') return _ok(lineNumber, pattern, '特拗');
      if (core == '仄平仄仄仄') return _err(lineNumber, pattern, '拗句');
      return _fallback(lineNumber, pattern, core);
  }
}

RegulatedVerseLineCheck _fallback(
  int lineNumber,
  String pattern,
  String core,
) {
  if (core[1] == core[3]) {
    return _err(lineNumber, pattern, '失律');
  }
  return _err(lineNumber, pattern, '拗句');
}

bool _isRescueSource(String pattern) {
  final core = _coreOf(pattern);
  return core == '仄仄仄平仄' ||
      core == '平仄仄平仄' ||
      core == '仄仄仄仄仄' ||
      core == '仄仄平仄仄';
}

bool _isRescueTarget(String pattern) {
  final core = _coreOf(pattern);
  return core == '仄平平仄平' || core == '平平平仄平';
}

void _applyCoupletRescue(List<RegulatedVerseLineCheck> lines) {
  for (var index = 0; index < lines.length - 1; index += 2) {
    final first = lines[index];
    final second = lines[index + 1];
    if (second.tags.contains('错脚')) {
      continue;
    }
    if (!_isRescueSource(first.pattern) || !_isRescueTarget(second.pattern)) {
      continue;
    }

    final firstCore = _coreOf(first.pattern);
    final secondCore = _coreOf(second.pattern);
    if (firstCore == '仄仄仄仄仄' || firstCore == '仄仄平仄仄') {
      lines[index] = _replaceWithGreen(first, '被救');
    }
    if (secondCore == '仄平平仄平') {
      lines[index + 1] = _addGreenTag(lines[index + 1], '相救');
    } else if (secondCore == '平平平仄平') {
      lines[index + 1] = _replaceWithGreen(second, '相救');
    }
  }
}

RegulatedVerseLineCheck _replaceWithGreen(
  RegulatedVerseLineCheck line,
  String tag,
) {
  return RegulatedVerseLineCheck(
    lineNumber: line.lineNumber,
    pattern: line.pattern,
    status: ProsodyLineStatus.ok,
    tags: <String>[tag],
    marks: <RegulatedVerseMark>[
      RegulatedVerseMark(
        start: 1,
        end: line.pattern.length,
        color: ProsodyCheckColor.green,
        label: tag,
      ),
    ],
  );
}

RegulatedVerseLineCheck _addGreenTag(
  RegulatedVerseLineCheck line,
  String tag,
) {
  final tags = <String>[
    ...line.tags,
    if (!line.tags.contains(tag)) tag,
  ];
  return RegulatedVerseLineCheck(
    lineNumber: line.lineNumber,
    pattern: line.pattern,
    status: ProsodyLineStatus.ok,
    tags: List.unmodifiable(tags),
    marks: <RegulatedVerseMark>[
      for (final mark in line.marks)
        if (mark.color != ProsodyCheckColor.red) mark,
      RegulatedVerseMark(
        start: 1,
        end: line.pattern.length,
        color: ProsodyCheckColor.green,
        label: tag,
      ),
    ],
  );
}

bool _shouldSkipDui(
  RegulatedVerseLineCheck first,
  RegulatedVerseLineCheck second,
) {
  return first.tags.contains('特拗') ||
      first.tags.contains('被救') ||
      second.tags.contains('相救');
}

List<int> _importantPositions(String pattern) {
  return pattern.length == 5 ? const <int>[1, 3] : const <int>[1, 3, 5];
}

List<RegulatedVerseRelationCheck> _analyzeRelations(
  List<RegulatedVerseLineCheck> lines,
) {
  final relations = <RegulatedVerseRelationCheck>[];
  for (var index = 0; index < lines.length - 1; index += 2) {
    final first = lines[index];
    final second = lines[index + 1];
    if (first.tags.contains('错脚') || second.tags.contains('错脚')) {
      continue;
    }
    if (!_shouldSkipDui(first, second) &&
        _importantPositions(first.pattern)
            .any((position) => first.pattern[position] == second.pattern[position])) {
      relations.add(
        RegulatedVerseRelationCheck(
          firstLine: first.lineNumber,
          secondLine: second.lineNumber,
          tag: '失对',
          color: ProsodyCheckColor.red,
        ),
      );
    }
  }

  for (var index = 1; index < lines.length - 1; index += 2) {
    final previousDui = lines[index];
    final nextChu = lines[index + 1];
    if (previousDui.tags.contains('错脚') || nextChu.tags.contains('错脚')) {
      continue;
    }
    if (previousDui.pattern[1] != nextChu.pattern[1]) {
      relations.add(
        RegulatedVerseRelationCheck(
          firstLine: previousDui.lineNumber,
          secondLine: nextChu.lineNumber,
          tag: '失粘',
          color: ProsodyCheckColor.green,
        ),
      );
    }
  }
  return relations;
}
