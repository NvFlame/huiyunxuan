import '../models/poem.dart';

class PoemFingerprint {
  const PoemFingerprint({
    required this.exactContentHash,
    required this.workFingerprint,
    required this.contentShapeHash,
  });

  final String exactContentHash;
  final String workFingerprint;
  final String contentShapeHash;

  Map<String, Object?> toMap() {
    return {
      'exact_content_hash': exactContentHash,
      'work_fingerprint': workFingerprint,
      'content_shape_hash': contentShapeHash,
    };
  }
}

class DuplicatePoemCandidate {
  const DuplicatePoemCandidate({
    required this.poem,
    required this.collectionNames,
    required this.reason,
    required this.level,
  });

  final Poem poem;
  final List<String> collectionNames;
  final String reason;
  final DuplicatePoemMatchLevel level;
}

enum DuplicatePoemMatchLevel {
  exact,
  work,
  shape,
}

PoemFingerprint buildPoemFingerprint({
  required String author,
  required String content,
}) {
  // Title is deliberately excluded: the same work can circulate under aliases.
  final normalizedContent = _normalizeContentForExactHash(content);
  final lines = _effectiveContentLines(content);
  final firstLine = lines.isEmpty ? '' : lines.first;
  final lastLine = lines.isEmpty ? '' : lines.last;
  final compactText = lines.join('');
  final shapeSource = [
    firstLine,
    lastLine,
    compactText.length.toString(),
    lines.length.toString(),
  ].join('|');
  final normalizedAuthor = _normalizeReliableAuthor(author);
  final workSource = normalizedAuthor.isEmpty
      ? ''
      : [
          normalizedAuthor,
          firstLine,
          lastLine,
          compactText.length.toString(),
          lines.length.toString(),
        ].join('|');

  return PoemFingerprint(
    exactContentHash: normalizedContent.isEmpty
        ? ''
        : _stableHash(normalizedContent),
    workFingerprint: workSource.isEmpty ? '' : _stableHash(workSource),
    contentShapeHash: shapeSource.trim().isEmpty ? '' : _stableHash(shapeSource),
  );
}

PoemFingerprint buildPoemFingerprintFromPoem(Poem poem) {
  return buildPoemFingerprint(author: poem.author, content: poem.content);
}

bool isUnreliableAuthor(String author) {
  final text = _normalizeCommonText(author);
  if (text.isEmpty) {
    return true;
  }
  const unreliableAuthors = {
    '佚名',
    '无名氏',
    '无名',
    '匿名',
    '阙名',
    '不详',
    '未知',
    '失名',
    '古人',
  };
  return unreliableAuthors.contains(text);
}

String _normalizeReliableAuthor(String author) {
  final text = _normalizeCommonText(author);
  return isUnreliableAuthor(text) ? '' : text;
}

String _normalizeContentForExactHash(String content) {
  return _normalizeCommonText(content).replaceAll(RegExp(r'\s+'), '');
}

List<String> _effectiveContentLines(String content) {
  final normalized = _normalizeCommonText(content);
  final rawLines = normalized.split(RegExp(r'\r?\n'));
  final lines = <String>[];
  for (final rawLine in rawLines) {
    final line = rawLine.replaceAll(RegExp(r'\s+'), '');
    if (line.isEmpty) {
      continue;
    }
    final trimmed = line
        .replaceAll(RegExp(r'^[，。！？；：、,.!?;:\s]+'), '')
        .replaceAll(RegExp(r'[，。！？；：、,.!?;:\s]+$'), '');
    if (trimmed.isNotEmpty) {
      lines.add(trimmed);
    }
  }
  if (lines.length > 1) {
    return lines;
  }

  final clauses = normalized
      .split(RegExp(r'[。！？；!?;]+'))
      .map((item) => item.replaceAll(RegExp(r'\s+'), ''))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return clauses.isEmpty ? lines : clauses;
}

String _normalizeCommonText(String text) {
  return text
      .trim()
      .replaceAll('　', ' ')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('【', '[')
      .replaceAll('】', ']')
      .replaceAll('《', '')
      .replaceAll('》', '')
      .replaceAll('〈', '')
      .replaceAll('〉', '')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _stableHash(String value) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0x7fffffffffffffff;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
