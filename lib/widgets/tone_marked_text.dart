import 'package:flutter/material.dart';

import '../models/poem.dart';
import '../services/rhyme_service.dart';
import '../services/regulated_verse_checker.dart';

class ToneMarkedLineText extends StatelessWidget {
  const ToneMarkedLineText({
    super.key,
    required this.line,
    required this.rhymeBook,
    this.lineNumber = 1,
    this.overridesJson = '',
    this.textStyle,
  });

  final String line;
  final String rhymeBook;
  final int lineNumber;
  final String overridesJson;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final tones = analyzeLineTones(
      line,
      rhymeBook,
      lineNumber: lineNumber,
      overridesJson: overridesJson,
    );
    if (tones.isEmpty) {
      return Text(line, style: textStyle);
    }

    final style = textStyle ?? Theme.of(context).textTheme.titleMedium;
    var toneIndex = 0;
    return Wrap(
      spacing: 5,
      runSpacing: 8,
      children: [
        for (final rune in line.runes)
          if (_isChineseRune(rune))
            _ToneMarkCell(
              tone: tones[toneIndex++],
              textStyle: style,
            )
          else if (String.fromCharCode(rune).trim().isNotEmpty)
            _PunctuationCell(
              character: String.fromCharCode(rune),
              textStyle: style,
            ),
      ],
    );
  }
}

class ToneMarkedPoemText extends StatelessWidget {
  const ToneMarkedPoemText({
    super.key,
    required this.poem,
    this.textStyle,
    this.showLineNumbers = true,
  });

  final Poem poem;
  final TextStyle? textStyle;
  final bool showLineNumbers;

  @override
  Widget build(BuildContext context) {
    final regulatedCheck = checkRegulatedVerse(poem);
    final lineChecksByNumber = {
      for (final line in regulatedCheck.lines) line.lineNumber: line,
    };
    final relationsByFirstLine = <int, List<RegulatedVerseRelationCheck>>{};
    for (final relation in regulatedCheck.relations) {
      relationsByFirstLine
          .putIfAbsent(relation.firstLine, () => <RegulatedVerseRelationCheck>[])
          .add(relation);
    }
    final lines = poem.content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    var lineNumber = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rawLine in lines)
          if (rawLine.trim().isEmpty)
            const _ToneStanzaDivider()
          else
            Builder(
              builder: (context) {
                lineNumber += 1;
                final currentLineNumber = lineNumber;
                final lineMarks = lineChecksByNumber[currentLineNumber]?.marks ??
                    const <RegulatedVerseMark>[];
                final relationLabels =
                    relationsByFirstLine[currentLineNumber] ??
                        const <RegulatedVerseRelationCheck>[];
                final lineRow = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showLineNumbers)
                      SizedBox(
                        width: _toneMarkedLineNumberWidth,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '$currentLineNumber',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: const Color(0xFF9A7B2F),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ToneMarkedLineText(
                        line: rawLine.trim(),
                        rhymeBook: poem.prosodyRhymeBook,
                        lineNumber: currentLineNumber,
                        overridesJson: poem.prosodyOverridesJson,
                        textStyle: textStyle,
                      ),
                    ),
                  ],
                );
                final lineContent = ToneMarkedLineIssueOverlay(
                  line: rawLine.trim(),
                  showLineNumbers: showLineNumbers,
                  marks: lineMarks,
                  relations: relationLabels,
                  lineTopPadding: 5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: lineRow,
                  ),
                );
                return lineContent;
              },
            ),
      ],
    );
  }
}

class ToneMarkedLineIssueOverlay extends StatelessWidget {
  const ToneMarkedLineIssueOverlay({
    super.key,
    required this.line,
    required this.showLineNumbers,
    required this.marks,
    required this.relations,
    this.lineTopPadding = 0,
    required this.child,
  });

  final String line;
  final bool showLineNumbers;
  final List<RegulatedVerseMark> marks;
  final List<RegulatedVerseRelationCheck> relations;
  final double lineTopPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final labels = _visibleLineLabels(marks);
    if (labels.isEmpty && relations.isEmpty) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (labels.isNotEmpty)
              Positioned(
                left: _clampIssueLeft(
                  _issueAnchorLeft(line, showLineNumbers: showLineNumbers),
                  constraints.maxWidth,
                ),
                top: _issueTop(line) + lineTopPadding,
                child: _IssueDot(labels: labels),
              ),
            for (final relation in relations)
              Positioned(
                left: _clampRelationLineLeft(
                  _relationLineLeft(line, showLineNumbers: showLineNumbers),
                  constraints.maxWidth,
                  minWidth: _chineseCount(line) >= 7 ? 44 : 72,
                ),
                right: _relationLineRight(line),
                bottom: 0,
                height: 18,
                child: _RelationIssueLine(relation: relation),
              ),
          ],
        );
      },
    );
  }
}

const double _toneMarkedLineNumberWidth = 28;
const double _toneMarkedChineseCellWidth = 26;
const double _toneMarkedPunctuationCellWidth = 14;
const double _toneMarkedCellSpacing = 5;

double _issueAnchorLeft(String line, {required bool showLineNumbers}) {
  final trimmed = line.trim();
  var width = showLineNumbers ? _toneMarkedLineNumberWidth : 0.0;
  var tokenCount = 0;
  var chineseCount = 0;
  for (final rune in trimmed.runes) {
    final character = String.fromCharCode(rune);
    if (character.trim().isEmpty) {
      continue;
    }
    if (tokenCount > 0) {
      width += _toneMarkedCellSpacing;
    }
    if (_isChineseRune(rune)) {
      width += _toneMarkedChineseCellWidth;
      chineseCount += 1;
    } else {
      width += _toneMarkedPunctuationCellWidth;
    }
    tokenCount += 1;
  }
  return width + (chineseCount >= 7 ? 56 : 16);
}

double _relationLineLeft(String line, {required bool showLineNumbers}) {
  final trimmed = line.trim();
  var width = showLineNumbers ? _toneMarkedLineNumberWidth : 0.0;
  var tokenCount = 0;
  var chineseCount = 0;
  double? punctuationLeft;
  for (final rune in trimmed.runes) {
    final character = String.fromCharCode(rune);
    if (character.trim().isEmpty) {
      continue;
    }
    if (tokenCount > 0) {
      width += _toneMarkedCellSpacing;
    }
    if (_isChineseRune(rune)) {
      width += _toneMarkedChineseCellWidth;
      chineseCount += 1;
    } else if (_isRelationPunctuation(character)) {
      punctuationLeft = width;
      width += _toneMarkedPunctuationCellWidth;
    } else {
      width += _toneMarkedPunctuationCellWidth;
    }
    tokenCount += 1;
  }
  if (punctuationLeft == null) {
    return width;
  }
  return punctuationLeft +
      _toneMarkedPunctuationCellWidth +
      (chineseCount >= 7 ? 30 : 0);
}

double _relationLineRight(String line) {
  return _chineseCount(line) >= 7 ? 0 : 6;
}

double _issueTop(String line) {
  return _chineseCount(line) >= 7 ? 3 : 3;
}

double _clampIssueLeft(double left, double maxWidth) {
  if (!maxWidth.isFinite) {
    return left;
  }
  final maxLeft = maxWidth - 30;
  if (maxLeft <= 0) {
    return left;
  }
  return left > maxLeft ? maxLeft : left;
}

double _clampRelationLineLeft(
  double left,
  double maxWidth, {
  required double minWidth,
}) {
  if (!maxWidth.isFinite) {
    return left;
  }
  final maxLeft = maxWidth - minWidth;
  if (maxLeft <= 0) {
    return left;
  }
  return left > maxLeft ? maxLeft : left;
}

int _chineseCount(String line) {
  var count = 0;
  for (final rune in line.runes) {
    if (_isChineseRune(rune)) {
      count += 1;
    }
  }
  return count;
}

class _IssueDot extends StatelessWidget {
  const _IssueDot({required this.labels});

  final List<_LineLabel> labels;

  @override
  Widget build(BuildContext context) {
    final hasRed = labels.any((label) => label.color == ProsodyCheckColor.red);
    final color = _colorForCheck(
      hasRed ? ProsodyCheckColor.red : ProsodyCheckColor.green,
    );
    return _IssueAnchor(
      lines: [
        for (final label in labels) label.text,
      ],
      color: color,
      child: SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: const SizedBox(width: 8, height: 8),
          ),
        ),
      ),
    );
  }
}

class _IssueAnchor extends StatefulWidget {
  const _IssueAnchor({
    required this.lines,
    required this.color,
    required this.child,
  });

  final List<String> lines;
  final Color color;
  final Widget child;

  @override
  State<_IssueAnchor> createState() => _IssueAnchorState();
}

class _IssueAnchorState extends State<_IssueAnchor> {
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _toggle() {
    if (_entry == null) {
      _show();
    } else {
      _hide();
    }
  }

  void _show() {
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize) {
      return;
    }

    final screenSize = MediaQuery.sizeOf(context);
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final maxLabelLength = widget.lines.fold<int>(
      0,
      (max, line) => line.length > max ? line.length : max,
    );
    final estimatedWidth = (maxLabelLength * 18 + 24).clamp(52, 150).toDouble();
    final left = _clampOverlayPosition(
      origin.dx + size.width + 5,
      6,
      screenSize.width - estimatedWidth - 6,
    );
    final top = _clampOverlayPosition(
      origin.dy + (size.height / 2) - 18,
      6,
      screenSize.height - 54,
    );

    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hide,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: widget.color.withOpacity(0.32)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x24000000),
                      blurRadius: 7,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  child: _IssuePopup(lines: widget.lines, color: widget.color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggle,
      child: widget.child,
    );
  }
}

double _clampOverlayPosition(double value, double min, double max) {
  if (max <= min) {
    return min;
  }
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

class _IssuePopup extends StatelessWidget {
  const _IssuePopup({required this.lines, required this.color});

  final List<String> lines;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RelationIssueLine extends StatelessWidget {
  const _RelationIssueLine({required this.relation});

  final RegulatedVerseRelationCheck relation;

  @override
  Widget build(BuildContext context) {
    final color = _colorForCheck(relation.color);
    return _IssueAnchor(
      lines: [relation.tag],
      color: color,
      child: CustomPaint(
        painter: _RelationIssuePainter(color: color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RelationIssuePainter extends CustomPainter {
  const _RelationIssuePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.75)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final y = size.height - 1;
    canvas.drawLine(
      Offset.zero.translate(0, y),
      Offset(size.width - 8, y),
      paint,
    );
    canvas.drawCircle(Offset(size.width - 4, y), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RelationIssuePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ToneMarkCell extends StatelessWidget {
  const _ToneMarkCell({required this.tone, this.textStyle});

  final ToneCharacter tone;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone.mark) {
      '平' => const Color(0xFF275D77),
      '仄' => const Color(0xFF8A5200),
      '多' => const Color(0xFF9B4A00),
      _ => const Color(0xFF777777),
    };
    return SizedBox(
      width: 26,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tone.character,
            textAlign: TextAlign.center,
            style: textStyle?.copyWith(height: 1.15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            tone.mark,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  height: 1,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _PunctuationCell extends StatelessWidget {
  const _PunctuationCell({required this.character, this.textStyle});

  final String character;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Text(
          character,
          textAlign: TextAlign.center,
          style: textStyle?.copyWith(height: 1.15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ToneStanzaDivider extends StatelessWidget {
  const _ToneStanzaDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 10, 4, 10),
      child: Divider(
        height: 1,
        thickness: 0.8,
        color: Color(0xFFEEDC9A),
      ),
    );
  }
}

class _LineLabel {
  const _LineLabel(this.text, this.color);

  final String text;
  final ProsodyCheckColor color;
}

List<_LineLabel> _visibleLineLabels(List<RegulatedVerseMark> marks) {
  final labels = <_LineLabel>[];
  for (final mark in marks) {
    if (!_shouldShowLineLabel(mark)) {
      continue;
    }
    if (labels.any((item) => item.text == mark.label)) {
      continue;
    }
    labels.add(_LineLabel(mark.label, mark.color));
  }
  return labels;
}

bool _shouldShowLineLabel(RegulatedVerseMark mark) {
  if (mark.color == ProsodyCheckColor.red) {
    return true;
  }
  return mark.label == '半拗' ||
      mark.label == '自救' ||
      mark.label == '相救' ||
      mark.label == '被救' ||
      mark.label == '特拗' ||
      mark.label == '三仄尾';
}

Color _colorForCheck(ProsodyCheckColor color) {
  return color == ProsodyCheckColor.red
      ? const Color(0xFF9F241C)
      : const Color(0xFF4F7D25);
}

bool _isChineseRune(int rune) {
  return rune >= 0x4e00 && rune <= 0x9fff;
}

bool _isRelationPunctuation(String character) {
  return character == '，' ||
      character == '。' ||
      character == '！' ||
      character == '？';
}
