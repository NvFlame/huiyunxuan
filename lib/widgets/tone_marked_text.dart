import 'package:flutter/material.dart';

import '../models/poem.dart';
import '../services/rhyme_service.dart';

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
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showLineNumbers)
                        SizedBox(
                          width: 28,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '$lineNumber',
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
                          lineNumber: lineNumber,
                          overridesJson: poem.prosodyOverridesJson,
                          textStyle: textStyle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ],
    );
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

bool _isChineseRune(int rune) {
  return rune >= 0x4e00 && rune <= 0x9fff;
}
