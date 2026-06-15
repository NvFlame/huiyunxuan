import 'package:flutter/material.dart';

import '../models/poem.dart';
import '../services/prosody_service.dart';
import '../services/rhyme_service.dart';

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.fact_check_outlined,
                  color: Color(0xFF8A6900),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('格律', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProsodyChip(
                  label: prosodySystemLabel(poem.prosodySystem),
                  icon: Icons.category_outlined,
                ),
                if (form.isNotEmpty)
                  _ProsodyChip(label: form, icon: Icons.format_list_numbered),
                if (rhymeBook.isNotEmpty)
                  _ProsodyChip(label: rhymeBook, icon: Icons.library_books),
                if (rhymeAnalysis.primaryRhyme.isNotEmpty)
                  _ProsodyChip(
                    label: '韵部：${rhymeAnalysis.primaryRhyme}',
                    icon: rhymeAnalysis.needsConfirmation
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
              rhymeAnalysis.applicable
                  ? rhymeAnalysis.summary
                  : _statusText(poem),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.55,
                color: const Color(0xFF4F3B12),
              ),
            ),
            if (rhymeAnalysis.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ProsodyDetailList(details: rhymeAnalysis.details),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: showToneDetails,
              onChanged: onToneDetailsChanged,
              title: const Text('逐字平仄'),
              subtitle: const Text('打开后显示每一句每个字的平仄初判。'),
            ),
            if (onManualCalibration != null || onAiCalibration != null) ...[
              const SizedBox(height: 4),
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
                      onPressed: calibrationBusy ? null : onAiCalibration,
                      icon: calibrationBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
    );
  }

  String _statusText(Poem poem) {
    switch (poem.prosodySystem) {
      case Poem.prosodySystemRegulatedVerse:
        return '当前按近体诗显示。平仄、粘对和多音字校验会在后续补上。';
      case Poem.prosodySystemCi:
        return '当前按词牌显示。词谱句式、平仄和押韵位置会在后续补上。';
      case Poem.prosodySystemQu:
        return '当前按曲牌显示。曲谱与中原音韵检查会在后续补上。';
      default:
        return '当前作品暂未启用详细格律检查。';
    }
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
  const _ProsodyChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: const Color(0xFFFFF4C7),
      side: const BorderSide(color: Color(0xFFE6C66A)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
