import '../models/poem.dart';
import 'prosody_override_service.dart';
import 'rhyme_book_data.dart';

class RhymeEntry {
  const RhymeEntry(this.label, this.tone);

  final String label;
  final RhymeTone tone;
}

class RhymeFoot {
  const RhymeFoot({
    required this.lineNumber,
    required this.character,
    required this.matches,
    this.pronunciationUncertain = false,
  });

  final int lineNumber;
  final String character;
  final List<RhymeEntry> matches;
  final bool pronunciationUncertain;

  bool get isUnknown => matches.isEmpty;
  bool get isAmbiguous => matches.length > 1;
  bool get needsPronunciationConfirmation =>
      pronunciationUncertain && matches.isNotEmpty;
}

class RhymeAnalysis {
  const RhymeAnalysis({
    required this.applicable,
    required this.needsConfirmation,
    required this.primaryRhyme,
    required this.summary,
    required this.details,
    required this.feet,
  });

  final bool applicable;
  final bool needsConfirmation;
  final String primaryRhyme;
  final String summary;
  final List<String> details;
  final List<RhymeFoot> feet;
}

class ToneCharacter {
  const ToneCharacter({
    required this.character,
    required this.mark,
  });

  final String character;
  final String mark;

  bool get isUnknown => mark == '?';
  bool get isAmbiguous => mark == '多';
}

class ProsodyCalibrationCandidate {
  const ProsodyCalibrationCandidate({
    required this.lineNumber,
    required this.charIndex,
    required this.character,
    required this.matches,
    required this.currentTone,
    required this.isRhymeFoot,
    this.existingOverride,
  });

  final int lineNumber;
  final int charIndex;
  final String character;
  final List<RhymeEntry> matches;
  final String currentTone;
  final bool isRhymeFoot;
  final ProsodyCharacterOverride? existingOverride;

  String get key => ProsodyOverrideStore.positionKey(lineNumber, charIndex);

  List<String> get rhymeOptions {
    return matches.map((entry) => entry.label).toSet().toList(growable: false);
  }

  bool get hasResolvedTone {
    final tone = existingOverride?.tone.trim() ?? '';
    return tone == '平' || tone == '仄';
  }

  bool get hasResolvedRhyme {
    return existingOverride?.rhyme.trim().isNotEmpty ?? false;
  }
}

class ToneLine {
  const ToneLine({
    required this.lineNumber,
    required this.characters,
  });

  final int lineNumber;
  final List<ToneCharacter> characters;
}

RhymeAnalysis analyzeRhyme(Poem poem) {
  if (!poem.prosodySupported || !poem.prosodyEnabled) {
    return const RhymeAnalysis(
      applicable: false,
      needsConfirmation: false,
      primaryRhyme: '',
      summary: '未显示格律。',
      details: [],
      feet: [],
    );
  }

  final rhymeBook = poem.prosodyRhymeBook.trim();
  if (rhymeBook == Poem.rhymeBookXinYun && xinYunGroups.isEmpty) {
    return const RhymeAnalysis(
      applicable: true,
      needsConfirmation: true,
      primaryRhyme: '待确认',
      summary: '新韵本地韵表尚未接入，当前仅记录为新韵查看。',
      details: ['后续接入新韵韵表后，可自动判断韵脚所属韵部。'],
      feet: [],
    );
  }

  switch (poem.prosodySystem) {
    case Poem.prosodySystemRegulatedVerse:
      return _analyzeRegulatedVerse(poem);
    case Poem.prosodySystemCi:
      return _analyzeCi(poem);
    default:
      return const RhymeAnalysis(
        applicable: false,
        needsConfirmation: false,
        primaryRhyme: '',
        summary: '当前体裁暂未接入韵部分析。',
        details: [],
        feet: [],
      );
  }
}

List<ToneLine> analyzeCharacterTones(Poem poem) {
  final lines = _contentLines(poem.content);
  final overrides = ProsodyOverrideStore.parse(poem.prosodyOverridesJson);
  return [
    for (var i = 0; i < lines.length; i += 1)
      ToneLine(
        lineNumber: i + 1,
        characters: _analyzeLineToneCharacters(
          line: lines[i],
          lineNumber: i + 1,
          rhymeBook: poem.prosodyRhymeBook,
          overrides: overrides,
        ),
      ),
  ];
}

List<ToneCharacter> analyzeLineTones(
  String line,
  String rhymeBook, {
  int lineNumber = 1,
  String overridesJson = '',
}) {
  return _analyzeLineToneCharacters(
    line: line,
    lineNumber: lineNumber,
    rhymeBook: rhymeBook,
    overrides: ProsodyOverrideStore.parse(overridesJson),
  );
}

RhymeAnalysis _analyzeRegulatedVerse(Poem poem) {
  final lines = _contentLines(poem.content);
  final overrides = ProsodyOverrideStore.parse(poem.prosodyOverridesJson);
  final requiredLineNumbers = _regulatedRhymeLineNumbers(lines.length);
  if (requiredLineNumbers.isEmpty) {
    return const RhymeAnalysis(
      applicable: true,
      needsConfirmation: true,
      primaryRhyme: '待确认',
      summary: '未能按绝句或律诗确定押韵句位。',
      details: ['请先确认正文是否按每句一行整理。'],
      feet: [],
    );
  }

  final feet = <RhymeFoot>[];
  for (final lineNumber in requiredLineNumbers) {
    final character = _lastChineseCharacter(lines[lineNumber - 1]);
    if (character == null) {
      continue;
    }
    feet.add(
      RhymeFoot(
        lineNumber: lineNumber,
        character: character,
        matches: _lookupRhymeForFoot(
          lineNumber: lineNumber,
          character: character,
          rhymeBook: poem.prosodyRhymeBook,
          overrides: overrides,
        ),
        pronunciationUncertain: _needsPronunciationConfirmation(character),
      ),
    );
  }

  final rhymeLabels = _rhymeLabels(feet);
  final primaryRhyme = rhymeLabels.isEmpty ? '' : rhymeLabels.join('、');
  final details = <String>[];
  final unknownFeet = feet.where((foot) => foot.isUnknown).toList();
  final ambiguousFeet = feet
      .where((foot) => foot.isAmbiguous || foot.needsPronunciationConfirmation)
      .toList();

  if (unknownFeet.isNotEmpty) {
    details.add(
      '待确认：${_formatFeet(unknownFeet)} 尚未收入本地韵表。',
    );
  }
  if (ambiguousFeet.isNotEmpty) {
    details.add(
      '多音或多韵：${_formatAmbiguousFeet(ambiguousFeet)}，需要后续按语境确认。',
    );
  }
  if (rhymeLabels.length > 1) {
    details.add(
      '韵部不一：当前韵脚分属“${rhymeLabels.join('、')}”。此处只作提示，不判定为错误。',
    );
  }
  details.add('依据：近体诗默认检查第 ${requiredLineNumbers.join('、')} 句韵脚，首句入韵会在后续模板阶段补充。');

  final needsConfirmation =
      primaryRhyme.isEmpty ||
      unknownFeet.isNotEmpty ||
      ambiguousFeet.isNotEmpty;
  return RhymeAnalysis(
    applicable: true,
    needsConfirmation: needsConfirmation,
    primaryRhyme: primaryRhyme.isEmpty ? '待确认' : primaryRhyme,
    summary: needsConfirmation
        ? '已识别近体诗韵脚，但仍有韵字需要人工确认。'
        : rhymeLabels.length > 1
            ? '韵脚已可识别，但分属多个韵部；暂只显示信息，不做审查判断。'
            : '韵脚集中在“$primaryRhyme”。',
    details: details,
    feet: feet,
  );
}

RhymeAnalysis _analyzeCi(Poem poem) {
  final overrides = ProsodyOverrideStore.parse(poem.prosodyOverridesJson);
  final feet = _sentenceEndingCharacters(poem.content)
      .map(
        (foot) => RhymeFoot(
          lineNumber: foot.lineNumber,
          character: foot.character,
          matches: _lookupRhymeForFoot(
            lineNumber: foot.lineNumber,
            character: foot.character,
            rhymeBook: poem.prosodyRhymeBook,
            overrides: overrides,
          ),
          pronunciationUncertain:
              _needsPronunciationConfirmation(foot.character),
        ),
      )
      .toList(growable: false);

  if (feet.isEmpty) {
    return const RhymeAnalysis(
      applicable: true,
      needsConfirmation: true,
      primaryRhyme: '待确认',
      summary: '未能识别词句句尾候选韵脚。',
      details: ['请确认正文是否保留了标点。'],
      feet: [],
    );
  }

  final rhymeLabels = _rhymeLabels(feet);
  final primaryRhyme = rhymeLabels.isEmpty ? '' : rhymeLabels.join('、');
  final details = <String>[
    _ciLinIndex.isEmpty
        ? '词林正韵数据尚未单独接入，当前借平水韵判断平仄，并按句末字估算候选韵部。'
        : '词谱尚未接入，当前只按句末字估算候选韵部，不能据此判定合格或出韵。',
  ];
  final unknownFeet = feet.where((foot) => foot.isUnknown).toList();
  final ambiguousFeet = feet
      .where((foot) => foot.isAmbiguous || foot.needsPronunciationConfirmation)
      .toList();
  if (unknownFeet.isNotEmpty) {
    details.add('待确认：${_formatFeet(unknownFeet)} 尚未收入本地词韵表。');
  }
  if (ambiguousFeet.isNotEmpty) {
    details.add('多音或多韵：${_formatAmbiguousFeet(ambiguousFeet)}。');
  }

  return RhymeAnalysis(
    applicable: true,
    needsConfirmation: true,
    primaryRhyme: primaryRhyme.isEmpty ? '待确认' : '$primaryRhyme 候选',
    summary: primaryRhyme.isEmpty
        ? '已进入词韵模式，但候选韵部仍需人工确认。'
        : '候选词韵为“$primaryRhyme”，待词谱接入后再做定格判断。',
    details: details,
    feet: feet,
  );
}

List<ProsodyCalibrationCandidate> findProsodyCalibrationCandidates(Poem poem) {
  if (!poem.prosodySupported || !poem.prosodyEnabled) {
    return const <ProsodyCalibrationCandidate>[];
  }

  final overrides = ProsodyOverrideStore.parse(poem.prosodyOverridesJson);
  final lines = _contentLines(poem.content);
  final rhymeLines = _candidateRhymeLineNumbers(poem, lines);
  final candidates = <ProsodyCalibrationCandidate>[];

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final lineNumber = lineIndex + 1;
    final rhymeFootIndex = _lastChineseCharacterIndex(lines[lineIndex]);
    var charIndex = 0;
    for (final rune in lines[lineIndex].runes) {
      if (!_isChineseRune(rune)) {
        continue;
      }
      charIndex += 1;
      final character = String.fromCharCode(rune);
      final matches = _lookupRhyme(character, poem.prosodyRhymeBook);
      final mark = _toneMarkFromMatches(matches);
      final isRhymeFoot =
          rhymeFootIndex == charIndex && rhymeLines[lineNumber] == character;
      final existing = overrides.byPosition(
        lineNumber: lineNumber,
        charIndex: charIndex,
        character: character,
      );
      final needsTone = mark == '多' ||
          _needsPronunciationConfirmation(character) ||
          (existing?.tone.trim().isNotEmpty ?? false);
      final needsRhyme = isRhymeFoot &&
          (matches.length != 1 || (existing?.rhyme.trim().isNotEmpty ?? false));
      if (!needsTone && !needsRhyme) {
        continue;
      }
      candidates.add(
        ProsodyCalibrationCandidate(
          lineNumber: lineNumber,
          charIndex: charIndex,
          character: character,
          matches: matches,
          currentTone: mark,
          isRhymeFoot: isRhymeFoot,
          existingOverride: existing,
        ),
      );
    }
  }
  return List.unmodifiable(candidates);
}

List<String> _contentLines(String content) {
  return content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

List<int> _regulatedRhymeLineNumbers(int lineCount) {
  if (lineCount == 4) {
    return const [2, 4];
  }
  if (lineCount == 8) {
    return const [2, 4, 6, 8];
  }
  return const [];
}

String? _lastChineseCharacter(String line) {
  for (final rune in line.runes.toList().reversed) {
    if (_isChineseRune(rune)) {
      return String.fromCharCode(rune);
    }
  }
  return null;
}

int? _lastChineseCharacterIndex(String line) {
  var index = 0;
  int? lastIndex;
  for (final rune in line.runes) {
    if (_isChineseRune(rune)) {
      index += 1;
      lastIndex = index;
    }
  }
  return lastIndex;
}

bool _isChineseRune(int rune) {
  return rune >= 0x4e00 && rune <= 0x9fff;
}

List<String> _rhymeLabels(List<RhymeFoot> feet) {
  final labels = <String>{};
  for (final foot in feet) {
    for (final match in foot.matches) {
      labels.add(match.label);
    }
  }
  return labels.toList()..sort();
}

List<RhymeEntry> _lookupRhyme(String character, String rhymeBook) {
  final book = rhymeBook.trim();
  if (book == Poem.rhymeBookXinYun) {
    return _xinYunIndex[character] ?? const [];
  }
  if (book == Poem.rhymeBookCiLin) {
    return _ciLinIndex[character] ?? _pingShuiIndex[character] ?? const [];
  }
  return _pingShuiIndex[character] ?? const [];
}

List<RhymeEntry> _lookupRhymeForFoot({
  required int lineNumber,
  required String character,
  required String rhymeBook,
  required ProsodyOverrideStore overrides,
}) {
  final override = overrides.rhymeForLine(
    lineNumber: lineNumber,
    character: character,
  );
  if (override != null && override.rhyme.trim().isNotEmpty) {
    return [
      RhymeEntry(
        override.rhyme.trim(),
        override.tone.trim() == '平' ? RhymeTone.level : RhymeTone.oblique,
      ),
    ];
  }
  return _lookupRhyme(character, rhymeBook);
}

String _toneMarkForCharacter(String character, String rhymeBook) {
  return _toneMarkFromMatches(_lookupRhyme(character, rhymeBook));
}

List<ToneCharacter> _analyzeLineToneCharacters({
  required String line,
  required int lineNumber,
  required String rhymeBook,
  required ProsodyOverrideStore overrides,
}) {
  final tones = <ToneCharacter>[];
  var charIndex = 0;
  for (final rune in line.runes) {
    if (!_isChineseRune(rune)) {
      continue;
    }
    charIndex += 1;
    final character = String.fromCharCode(rune);
    final override = overrides.byPosition(
      lineNumber: lineNumber,
      charIndex: charIndex,
      character: character,
    );
    final overrideTone = override?.tone.trim() ?? '';
    tones.add(
      ToneCharacter(
        character: character,
        mark: overrideTone.isNotEmpty
            ? overrideTone
            : _toneMarkForCharacter(character, rhymeBook),
      ),
    );
  }
  return tones;
}

String _toneMarkFromMatches(List<RhymeEntry> matches) {
  if (matches.isEmpty) return '?';
  var hasLevel = false;
  var hasOblique = false;
  for (final match in matches) {
    if (match.tone == RhymeTone.level) {
      hasLevel = true;
    } else {
      hasOblique = true;
    }
  }
  if (hasLevel && hasOblique) {
    return '多';
  }
  if (hasLevel) {
    return '平';
  }
  if (hasOblique) {
    return '仄';
  }
  return '?';
}

Map<int, String> _candidateRhymeLineNumbers(Poem poem, List<String> lines) {
  if (poem.prosodySystem == Poem.prosodySystemRegulatedVerse) {
    return {
      for (final lineNumber in _regulatedRhymeLineNumbers(lines.length))
        if (lineNumber <= lines.length)
          lineNumber: _lastChineseCharacter(lines[lineNumber - 1]) ?? '',
    };
  }
  if (poem.prosodySystem == Poem.prosodySystemCi) {
    return {
      for (final foot in _sentenceEndingCharacters(poem.content))
        foot.lineNumber: foot.character,
    };
  }
  return const <int, String>{};
}

String _formatFeet(List<RhymeFoot> feet) {
  return feet.map((foot) => '第${foot.lineNumber}句“${foot.character}”').join('、');
}

String _formatAmbiguousFeet(List<RhymeFoot> feet) {
  return feet
      .map(
        (foot) {
          final labels = foot.matches.map((entry) => entry.label).join('/');
          final suffix = foot.needsPronunciationConfirmation ? '，多音待确认' : '';
          return '第${foot.lineNumber}句“${foot.character}”($labels$suffix)';
        },
      )
      .join('、');
}

bool _needsPronunciationConfirmation(String character) {
  return _pronunciationUncertainCharacters.contains(character);
}

List<_SentenceFoot> _sentenceEndingCharacters(String content) {
  final feet = <_SentenceFoot>[];
  final lines = _contentLines(content);
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    var lastCandidate = '';
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      if (_isChineseRune(rune)) {
        lastCandidate = char;
        continue;
      }
      if (_sentenceEndingMarks.contains(char) && lastCandidate.isNotEmpty) {
        feet.add(_SentenceFoot(lineNumber: i + 1, character: lastCandidate));
        lastCandidate = '';
      }
    }
    if (lastCandidate.isNotEmpty) {
      feet.add(_SentenceFoot(lineNumber: i + 1, character: lastCandidate));
    }
  }
  return feet;
}

const _sentenceEndingMarks = <String>{'。', '？', '！', '；', '，', '、'};
const _pronunciationUncertainCharacters = <String>{
  '重',
  '行',
  '还',
  '看',
  '过',
  '为',
  '思',
  '论',
  '传',
  '应',
  '任',
  '降',
  '骑',
  '长',
  '中',
  '燕',
  '少',
  '处',
};

class _SentenceFoot {
  const _SentenceFoot({required this.lineNumber, required this.character});

  final int lineNumber;
  final String character;
}

final Map<String, List<RhymeEntry>> _pingShuiIndex = _buildIndex(pingShuiGroups);
final Map<String, List<RhymeEntry>> _xinYunIndex = _buildIndex(xinYunGroups);

final Map<String, List<RhymeEntry>> _ciLinIndex = _buildIndex(ciLinGroups);

Map<String, List<RhymeEntry>> _buildIndex(List<RhymeBookGroup> groups) {
  final index = <String, List<RhymeEntry>>{};
  for (final group in groups) {
    for (final rune in group.characters.runes) {
      final char = String.fromCharCode(rune);
      if (!_isChineseRune(rune)) {
        continue;
      }
      final entries = index.putIfAbsent(char, () => <RhymeEntry>[]);
      if (!entries.any(
        (entry) => entry.label == group.label && entry.tone == group.tone,
      )) {
        entries.add(RhymeEntry(group.label, group.tone));
      }
    }
  }
  return index;
}
