class PoemTextFormatIssue {
  const PoemTextFormatIssue(this.message);

  final String message;
}

PoemTextFormatIssue? validatePoemTextFormat({
  required String title,
  required String content,
  required String annotation,
}) {
  return validatePoemContentLayout(content, title: title) ??
      validatePoemAnnotationLineNumbers(
        content: content,
        annotation: annotation,
      );
}

PoemTextFormatIssue? validatePoemContentLayout(
  String content, {
  String title = '',
}) {
  final lines = _contentLines(content);
  if (lines.isEmpty) {
    return const PoemTextFormatIssue('正文内容为空。');
  }

  final joined = lines.join('');
  final hasChineseText = RegExp(r'[\u4e00-\u9fff]').hasMatch(joined);
  final hasPunctuation = RegExp(r'[，。？！；：,.?!;:]').hasMatch(joined);
  if (hasChineseText && !hasPunctuation) {
    return const PoemTextFormatIssue(
      '正文没有逗号、句号、问号、叹号等现代标点。请依据带标点的权威整理本重新生成，不要在换行时删除标点。',
    );
  }

  if (!_looksLikeCiOrQuTitle(title)) {
    for (var index = 0; index < lines.length; index += 1) {
      final suggestion = _splitStandardVerseLine(lines[index]);
      if (suggestion == null) {
        continue;
      }
      return PoemTextFormatIssue(
        '正文第 ${index + 1} 行像是把多个诗句写在同一行：${lines[index]}\n'
        '请拆成：\n${suggestion.join('\n')}',
      );
    }
  }

  return null;
}

PoemTextFormatIssue? validatePoemAnnotationLineNumbers({
  required String content,
  required String annotation,
}) {
  final trimmedAnnotation = annotation.trim();
  if (trimmedAnnotation.isEmpty) {
    return null;
  }

  final contentLineCount = _contentLines(content).length;
  if (contentLineCount == 0) {
    return const PoemTextFormatIssue('原文内容为空，无法校验注释行号。');
  }

  final annotationLines = trimmedAnnotation
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  final linePattern = RegExp(r'^\[(\d+)\]\s*\S');

  for (var index = 0; index < annotationLines.length; index += 1) {
    final line = annotationLines[index].trim();
    final match = linePattern.firstMatch(line);
    if (match == null) {
      return PoemTextFormatIssue(
        '注释第 ${index + 1} 行没有以 [行号] 开头：$line',
      );
    }

    final lineNumber = int.tryParse(match.group(1)!);
    if (lineNumber == null ||
        lineNumber < 0 ||
        lineNumber > contentLineCount) {
      return PoemTextFormatIssue(
        '注释第 ${index + 1} 行使用了 [$lineNumber]，但原文只有 $contentLineCount 个非空行；[0] 仅用于标题注释。',
      );
    }
  }

  return null;
}

String normalizePoemContentLayout(
  String content, {
  String title = '',
}) {
  final rawLines = content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final lines = <String>[];
  final canSplitByStandardVerse = !_looksLikeCiOrQuTitle(title);

  for (final rawLine in rawLines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      if (lines.isNotEmpty && lines.last.isNotEmpty) {
        lines.add('');
      }
      continue;
    }

    final splitLines =
        canSplitByStandardVerse ? _splitStandardVerseLine(line) : null;
    if (splitLines == null) {
      lines.add(line);
    } else {
      lines.addAll(splitLines);
    }
  }

  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n').trim();
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

List<String>? _splitStandardVerseLine(String line) {
  final segments = _splitAtClausePunctuation(line);
  if (segments.length < 2) {
    return null;
  }

  final counts = segments.map(_chineseCharCount).toList(growable: false);
  if (counts.any((count) => count == 0)) {
    return null;
  }

  final firstCount = counts.first;
  final isStandardLength = firstCount == 4 || firstCount == 5 || firstCount == 7;
  if (!isStandardLength || counts.any((count) => count != firstCount)) {
    return null;
  }

  return segments;
}

List<String> _splitAtClausePunctuation(String line) {
  final normalized = line.trim();
  if (normalized.isEmpty) {
    return const <String>[];
  }

  final punctuation = RegExp(r'[，。？！；：,.?!;:]');
  final segments = <String>[];
  final buffer = StringBuffer();

  for (final rune in normalized.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(char);
    if (punctuation.hasMatch(char)) {
      final segment = buffer.toString().trim();
      if (segment.isNotEmpty) {
        segments.add(segment);
      }
      buffer.clear();
    }
  }

  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) {
    segments.add(tail);
  }

  return segments;
}

int _chineseCharCount(String text) {
  var count = 0;
  for (final rune in text.runes) {
    if (rune >= 0x4e00 && rune <= 0x9fff) {
      count += 1;
    }
  }
  return count;
}

bool _looksLikeCiOrQuTitle(String title) {
  final normalized = title.trim();
  if (normalized.isEmpty) {
    return false;
  }
  if (normalized.contains('·') || normalized.contains('・')) {
    return true;
  }

  const tuneNames = <String>{
    '永遇乐',
    '念奴娇',
    '水调歌头',
    '满江红',
    '虞美人',
    '蝶恋花',
    '鹊桥仙',
    '江城子',
    '浣溪沙',
    '卜算子',
    '如梦令',
    '声声慢',
    '青玉案',
    '雨霖铃',
    '破阵子',
    '渔家傲',
    '苏幕遮',
    '定风波',
    '西江月',
    '临江仙',
    '菩萨蛮',
    '沁园春',
    '扬州慢',
    '天净沙',
    '山坡羊',
  };
  return tuneNames.any((name) => normalized.startsWith(name));
}
