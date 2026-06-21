import 'package:flutter/material.dart';

import '../models/poem.dart';
import '../services/ci_pattern_service.dart';
import '../services/prosody_service.dart';
import '../services/rhyme_service.dart';
import '../services/regulated_verse_checker.dart';

class ProsodyPanel extends StatelessWidget {
  const ProsodyPanel({
    super.key,
    required this.poem,
    this.showToneDetails = false,
    this.onToneDetailsChanged,
    this.onManualCalibration,
    this.onAiCalibration,
    this.calibrationBusy = false,
  });

  final Poem poem;
  final bool showToneDetails;
  final ValueChanged<bool>? onToneDetailsChanged;
  final VoidCallback? onManualCalibration;
  final VoidCallback? onAiCalibration;
  final bool calibrationBusy;

  @override
  Widget build(BuildContext context) {
    if (!poem.prosodySupported || !poem.prosodyEnabled) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final form = poem.prosodyForm.trim();
    final rhymeBook = poem.prosodyRhymeBook.trim();
    final note = poem.prosodyNote.trim();
    final verificationLabel = _verificationLabel(poem);
    final rhymeAnalysis = analyzeRhyme(poem);
    final regulatedCheck = checkRegulatedVerse(poem);
    final ciCheck = checkCiPattern(poem);
    final isRegulatedVerse =
        poem.prosodySystem == Poem.prosodySystemRegulatedVerse;
    final isCi = poem.prosodySystem == Poem.prosodySystemCi;
    final isStructuredProsody = isRegulatedVerse || isCi;
    final displayForm = regulatedCheck.applicable
        ? regulatedCheck.displayForm
        : ciCheck.applicable
            ? ciCheck.displayForm
            : form;
    final formChecked = regulatedCheck.applicable || ciCheck.applicable;
    final formUnresolved = regulatedCheck.applicable
        ? regulatedCheck.unresolved
        : ciCheck.applicable
            ? ciCheck.unresolved
            : false;
    final formOk = regulatedCheck.applicable
        ? regulatedCheck.ok
        : ciCheck.applicable
            ? ciCheck.ok
            : false;
    final unsupportedCiPattern =
        ciCheck.applicable && !ciCheck.supportedPattern;
    final usesCiPatternRhyme = ciCheck.applicable && ciCheck.supportedPattern;
    final primaryRhyme = unsupportedCiPattern
        ? ''
        : usesCiPatternRhyme
            ? ciCheck.primaryRhyme
            : rhymeAnalysis.primaryRhyme;
    final rhymeNeedsConfirmation = usesCiPatternRhyme
        ? ciCheck.unresolved
        : rhymeAnalysis.needsConfirmation;
    final details = unsupportedCiPattern
        ? <String>[]
        : <String>[
            if (ciCheck.applicable) ...ciCheck.details,
            if (!ciCheck.applicable || !ciCheck.supportedPattern)
              ...rhymeAnalysis.details,
          ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: const Icon(
            Icons.fact_check_outlined,
            color: Color(0xFF8A6900),
          ),
          title: Text('格律', style: theme.textTheme.titleMedium),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: showToneDetails,
                    onChanged: onToneDetailsChanged,
                    title: Text(isStructuredProsody ? '格律审查' : '逐字平仄'),
                    subtitle: Text(
                      isRegulatedVerse
                          ? '打开后在正文中显示逐字平仄；平仄全部确定后自动进行正格审查。'
                          : isCi
                              ? '打开后在正文中显示逐字平仄，并按已接入词谱自动校对。'
                          : '打开后显示每一句每个字的平仄初判。',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ProsodyChip(
                        label: prosodySystemLabel(poem.prosodySystem),
                        icon: Icons.category_outlined,
                      ),
                      if (displayForm.isNotEmpty && !unsupportedCiPattern)
                        _ProsodyChip(
                          label: displayForm,
                          icon:
                              formChecked && !formOk
                                  ? Icons.report_problem_outlined
                                  : Icons.format_list_numbered,
                          color: formChecked && !formUnresolved
                              ? (formOk
                                  ? const Color(0xFFE9F7EA)
                                  : const Color(0xFFFFE9E4))
                              : null,
                        ),
                      if (rhymeBook.isNotEmpty)
                        _ProsodyChip(
                          label: rhymeBook,
                          icon: Icons.library_books,
                        ),
                      if (primaryRhyme.isNotEmpty)
                        _ProsodyChip(
                          label: '韵部：$primaryRhyme',
                          icon: rhymeNeedsConfirmation
                              ? Icons.help_outline
                              : Icons.check_circle_outline,
                        ),
                      if (verificationLabel.isNotEmpty)
                        _ProsodyChip(
                          label: verificationLabel,
                          icon: Icons.verified_outlined,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _summaryText(
                      poem: poem,
                      rhymeAnalysis: rhymeAnalysis,
                      regulatedCheck: regulatedCheck,
                      ciCheck: ciCheck,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.55,
                      color: const Color(0xFF4F3B12),
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ProsodyDetailList(details: details),
                  ],
                  if (note.isNotEmpty && !unsupportedCiPattern) ...[
                    const SizedBox(height: 8),
                    Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ],
                  if (onManualCalibration != null ||
                      onAiCalibration != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (onManualCalibration != null)
                          OutlinedButton.icon(
                            onPressed:
                                calibrationBusy ? null : onManualCalibration,
                            icon: const Icon(Icons.tune_outlined),
                            label: const Text('人工校准'),
                          ),
                        if (onAiCalibration != null)
                          FilledButton.tonalIcon(
                            onPressed:
                                calibrationBusy ? null : onAiCalibration,
                            icon: calibrationBusy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_fix_high_outlined),
                            label: const Text('智能校准'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(Poem poem) {
    switch (poem.prosodySystem) {
      case Poem.prosodySystemRegulatedVerse:
        return '当前按近体诗显示。平仄、粘对和多音字校验会在后续补上。';
      case Poem.prosodySystemCi:
        return '当前按词牌显示；已接入词谱时可自动校对句式、平仄、押韵和叠句。';
      case Poem.prosodySystemQu:
        return '当前按曲牌显示。曲谱与中原音韵检查会在后续补上。';
      default:
        return '当前作品暂未启用详细格律检查。';
    }
  }

  String _summaryText({
    required Poem poem,
    required RhymeAnalysis rhymeAnalysis,
    required RegulatedVerseCheck regulatedCheck,
    required CiPatternCheck ciCheck,
  }) {
    if (regulatedCheck.applicable) {
      return regulatedCheck.summary;
    }
    if (ciCheck.applicable) {
      return ciCheck.summary;
    }
    if (rhymeAnalysis.applicable) {
      return rhymeAnalysis.summary;
    }
    return _statusText(poem);
  }

  String _verificationLabel(Poem poem) {
    if (poem.prosodyOverridesJson.trim().isEmpty &&
        poem.prosodyVerifiedBy.trim().isEmpty &&
        poem.prosodyVerifiedAt == null) {
      return '';
    }
    final source = poem.prosodyVerifiedBy.trim();
    if (source == 'agent') {
      return '智能体校准';
    }
    if (source == 'user') {
      return '人工校准';
    }
    return '已校准';
  }
}

class _ProsodyDetailList extends StatelessWidget {
  const _ProsodyDetailList({required this.details});

  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          height: 1.5,
          color: const Color(0xFF6A5219),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(detail, style: textStyle),
          ),
      ],
    );
  }
}

class _ProsodyChip extends StatelessWidget {
  const _ProsodyChip({required this.label, required this.icon, this.color});

  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 132;
    final maxWidth = available < 180.0
        ? 180.0
        : available > 360.0
            ? 360.0
            : available;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? const Color(0xFFFFF4C7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE6C66A)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF8A6900)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4F3B12),
                        height: 1.25,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
