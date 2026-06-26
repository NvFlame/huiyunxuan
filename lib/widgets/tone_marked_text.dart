import 'package:flutter/material.dart';

import '../models/poem.dart';
import '../services/ci_pattern_service.dart';
import '../services/rhyme_service.dart';
import '../services/regulated_verse_checker.dart';

class ToneMarkedLineText extends StatelessWidget {
  const ToneMarkedLineText({
    super.key,
    required this.line,
    required this.rhymeBook,
    this.lineNumber = 1,
    this.overridesJson = '',
    this.marks = const <RegulatedVerseMark>[],
    this.textStyle,
  });

  final String line;
  final String rhymeBook;
  final int lineNumber;
  final String overridesJson;
  final List<RegulatedVerseMark> marks;
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
    final cells = _buildToneDisplayCells(line, tones, marks);
    return LayoutBuilder(
      builder: (context, constraints) {
        final forceSingleLine = _isSevenCharacterLine(line) &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0;
        final compact = forceSingleLine && constraints.maxWidth < 230;
        if (forceSingleLine) {
          return SizedBox(
            width: constraints.maxWidth,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildToneDisplayRowChildren(
                  cells,
                  style,
                  spacing: compact ? 3 : 5,
                ),
              ),
            ),
          );
        }
        return Wrap(
          spacing: 5,
          runSpacing: 8,
          children: [
            for (final cell in cells)
              _buildToneDisplayWidget(cell, style),
          ],
        );
      },
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
    final ciCheck = checkCiPattern(poem);
    final lineChecksByNumber = {
      for (final line in regulatedCheck.lines) line.lineNumber: line,
    };
    final ciLineChecksByNumber = {
      for (final line in ciCheck.lines) line.lineNumber: line,
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
                    ciLineChecksByNumber[currentLineNumber]?.marks ??
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
                        marks: lineMarks,
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
        final useRightEdgeIssueAnchor =
            labels.isNotEmpty && _usesRightEdgeIssueAnchor(line);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (useRightEdgeIssueAnchor)
              Padding(
                padding: const EdgeInsets.only(right: _toneMarkedIssueLaneWidth),
                child: child,
              )
            else
              child,
            if (labels.isNotEmpty)
              if (useRightEdgeIssueAnchor)
                Positioned(
                  right: -2,
                  top: _issueTop(line) + lineTopPadding,
                  child: _IssueDot(labels: labels),
                )
              else
                Positioned(
                  left: _issueAnchorLeft(
                    line,
                    showLineNumbers: showLineNumbers,
                    maxWidth: constraints.maxWidth,
                  ),
                  top: _issueTop(line) + lineTopPadding,
                  child: _IssueDot(labels: labels),
                ),
            for (final relation in relations)
              Positioned(
                right: _relationMarkerRight(line),
                bottom: -2,
                width: 22,
                height: 22,
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
const double _toneMarkedIssueLaneWidth = 30;

bool _isSevenCharacterLine(String line) => _chineseCount(line) == 7;

bool _usesRightEdgeIssueAnchor(String line) => _isSevenCharacterLine(line);

double _issueAnchorLeft(
  String line, {
  required bool showLineNumbers,
  required double maxWidth,
}) {
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
  final left = width + (chineseCount >= 7 ? 56 : 16);
  if (!maxWidth.isFinite) {
    return left;
  }
  final maxLeft = maxWidth - 30;
  if (maxLeft <= 0) {
    return left;
  }
  return left > maxLeft ? maxLeft : left;
}

double _relationLineLeft(
  String line, {
  required bool showLineNumbers,
  required double maxWidth,
}) {
  if (_isSevenCharacterLine(line) && maxWidth.isFinite) {
    return maxWidth - 58;
  }
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
  final left = punctuationLeft +
      _toneMarkedPunctuationCellWidth +
      (chineseCount >= 7 ? 30 : 0);
  if (!maxWidth.isFinite) {
    return left;
  }
  const minWidth = 72.0;
  final maxLeft = maxWidth - minWidth;
  if (maxLeft <= 0) {
    return left;
  }
  return left > maxLeft ? maxLeft : left;
}

double _relationLineRight(String line) {
  return _isSevenCharacterLine(line) ? 10 : 6;
}

double _relationMarkerRight(String line) {
  return _isSevenCharacterLine(line) ? -1 : 2;
}

double _issueTop(String line) {
  return _isSevenCharacterLine(line) ? 3 : 3;
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

List<_ToneDisplayCell> _buildToneDisplayCells(
  String line,
  List<ToneCharacter> tones,
  List<RegulatedVerseMark> marks,
) {
  final cells = <_ToneDisplayCell>[];
  var toneIndex = 0;
  for (final rune in line.runes) {
    final character = String.fromCharCode(rune);
    if (character.trim().isEmpty) {
      continue;
    }
    if (_isChineseRune(rune)) {
      if (toneIndex >= tones.length) {
        continue;
      }
      toneIndex += 1;
      cells.add(
        _ToneDisplayCell(
          tone: tones[toneIndex - 1],
          issue: _characterIssueForIndex(marks, toneIndex),
        ),
      );
      continue;
    }
    if (_isLineEndPunctuation(character) && cells.isNotEmpty) {
      final last = cells.removeLast();
      cells.add(last.copyWith(trailingText: last.trailingText + character));
    } else {
      cells.add(_ToneDisplayCell.trailing(character));
    }
  }
  return cells;
}

List<Widget> _buildToneDisplayRowChildren(
  List<_ToneDisplayCell> cells,
  TextStyle? style, {
  required double spacing,
}) {
  final children = <Widget>[];
  for (var index = 0; index < cells.length; index += 1) {
    if (index > 0) {
      children.add(SizedBox(width: spacing));
    }
    children.add(_buildToneDisplayWidget(cells[index], style));
  }
  return children;
}

Widget _buildToneDisplayWidget(_ToneDisplayCell cell, TextStyle? style) {
  if (cell.tone != null) {
    return _ToneMarkCell(
      tone: cell.tone!,
      issue: cell.issue,
      trailingText: cell.trailingText,
      textStyle: style,
    );
  }
  return _PunctuationCell(
    character: cell.trailingText,
    textStyle: style,
  );
}

class _ToneDisplayCell {
  const _ToneDisplayCell({
    required this.tone,
    required this.issue,
    this.trailingText = '',
  });

  const _ToneDisplayCell.trailing(String text)
      : tone = null,
        issue = _CharacterIssue.none,
        trailingText = text;

  final ToneCharacter? tone;
  final _CharacterIssue issue;
  final String trailingText;

  _ToneDisplayCell copyWith({String? trailingText}) {
    return _ToneDisplayCell(
      tone: tone,
      issue: issue,
      trailingText: trailingText ?? this.trailingText,
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
        child: const SizedBox(width: 22, height: 22),
      ),
    );
  }
}

class _RelationIssuePainter extends CustomPainter {
  const _RelationIssuePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 5.0;
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius, center.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RelationIssuePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ToneMarkCell extends StatelessWidget {
  const _ToneMarkCell({
    required this.tone,
    required this.issue,
    this.trailingText = '',
    this.textStyle,
  });

  final ToneCharacter tone;
  final _CharacterIssue issue;
  final String trailingText;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone.mark) {
      '平' => const Color(0xFF275D77),
      '仄' => const Color(0xFF8A5200),
      '多' => const Color(0xFF9B4A00),
      _ => const Color(0xFF777777),
    };
    final cellWidth =
        _toneMarkedChineseCellWidth + (trailingText.length * 12.0);
    return SizedBox(
      width: cellWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: _toneMarkedChineseCellWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tone.character,
                  textAlign: TextAlign.center,
                  style: textStyle?.copyWith(
                    height: 1.15,
                    color: issue.toneError ? const Color(0xFF9F241C) : null,
                    fontWeight: issue.rhymeError || issue.toneError
                        ? FontWeight.w900
                        : FontWeight.w600,
                  ),
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
          ),
          if (trailingText.isNotEmpty)
            Positioned(
              left: 23,
              top: 0,
              child: Text(
                trailingText,
                style: textStyle?.copyWith(
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
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

class _CharacterIssue {
  const _CharacterIssue({required this.toneError, required this.rhymeError});

  final bool toneError;
  final bool rhymeError;

  static const none = _CharacterIssue(toneError: false, rhymeError: false);
}

_CharacterIssue _characterIssueForIndex(
  List<RegulatedVerseMark> marks,
  int index,
) {
  var toneError = false;
  var rhymeError = false;
  for (final mark in marks) {
    if (index < mark.start || index > mark.end) {
      continue;
    }
    if (mark.color == ProsodyCheckColor.red && mark.label == '平仄') {
      toneError = true;
    }
    if (mark.color == ProsodyCheckColor.red && mark.label == '出韵') {
      rhymeError = true;
    }
  }
  if (!toneError && !rhymeError) {
    return _CharacterIssue.none;
  }
  return _CharacterIssue(toneError: toneError, rhymeError: rhymeError);
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
  if (mark.label == '平仄' || mark.label == '出韵') {
    return false;
  }
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
  return _isLineEndPunctuation(character);
}

bool _isLineEndPunctuation(String character) {
  return character == '，' ||
      character == '。' ||
      character == '！' ||
      character == '？' ||
      character == '、' ||
      character == '；' ||
      character == '：' ||
      character == ',' ||
      character == '.' ||
      character == '!' ||
      character == '?' ||
      character == ';' ||
      character == ':';
}
