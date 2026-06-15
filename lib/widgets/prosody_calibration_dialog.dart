import 'package:flutter/material.dart';

import '../models/poem.dart';
import '../services/prosody_override_service.dart';
import '../services/rhyme_book_data.dart';
import '../services/rhyme_service.dart';

class ProsodyCalibrationDialog extends StatefulWidget {
  const ProsodyCalibrationDialog({super.key, required this.poem});

  final Poem poem;

  @override
  State<ProsodyCalibrationDialog> createState() =>
      _ProsodyCalibrationDialogState();
}

class _ProsodyCalibrationDialogState extends State<ProsodyCalibrationDialog> {
  late final List<ProsodyCalibrationCandidate> _candidates;
  late final Map<String, ProsodyCharacterOverride> _drafts;

  @override
  void initState() {
    super.initState();
    _candidates = findProsodyCalibrationCandidates(widget.poem);
    _drafts = {
      for (final candidate in _candidates)
        candidate.key: candidate.existingOverride ??
            ProsodyCharacterOverride(
              lineNumber: candidate.lineNumber,
              charIndex: candidate.charIndex,
              character: candidate.character,
            ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('校准平仄与韵部'),
      content: SizedBox(
        width: double.maxFinite,
        child: _candidates.isEmpty
            ? Text('当前没有发现需要人工确认的多音字或多韵韵脚。', style: theme.textTheme.bodyMedium)
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _candidates.length,
                separatorBuilder: (context, index) => const Divider(height: 20),
                itemBuilder: (context, index) {
                  return _CandidateEditor(
                    candidate: _candidates[index],
                    value: _drafts[_candidates[index].key]!,
                    onChanged: (override) {
                      setState(() {
                        _drafts[_candidates[index].key] = override;
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _candidates.isEmpty
              ? null
              : () {
                  final current =
                      ProsodyOverrideStore.parse(widget.poem.prosodyOverridesJson);
                  final next = current.putAll(_drafts.values);
                  Navigator.pop(context, next.toJsonText());
                },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _CandidateEditor extends StatelessWidget {
  const _CandidateEditor({
    required this.candidate,
    required this.value,
    required this.onChanged,
  });

  final ProsodyCalibrationCandidate candidate;
  final ProsodyCharacterOverride value;
  final ValueChanged<ProsodyCharacterOverride> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rhymeOptions = <String>[
      '',
      if (value.rhyme.trim().isNotEmpty) value.rhyme.trim(),
      ...candidate.rhymeOptions,
    ].toSet().toList(growable: false);
    final toneValue = _toneOptions.contains(value.tone) ? value.tone : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '第 ${candidate.lineNumber} 行第 ${candidate.charIndex} 字 “${candidate.character}”'
          '${candidate.isRhymeFoot ? '（韵脚）' : ''}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _candidateDescription(candidate),
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF6A5219),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: toneValue,
                decoration: const InputDecoration(labelText: '平仄'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('不确定')),
                  DropdownMenuItem(value: '平', child: Text('平')),
                  DropdownMenuItem(value: '仄', child: Text('仄')),
                  DropdownMenuItem(value: '多', child: Text('多音')),
                ],
                onChanged: (tone) {
                  onChanged(value.copyWith(tone: tone ?? ''));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: rhymeOptions.contains(value.rhyme) ? value.rhyme : '',
                decoration: const InputDecoration(labelText: '韵部'),
                items: [
                  for (final option in rhymeOptions)
                    DropdownMenuItem(
                      value: option,
                      child: Text(option.isEmpty ? '不指定' : option),
                    ),
                ],
                onChanged: (rhyme) {
                  onChanged(value.copyWith(rhyme: rhyme ?? ''));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: value.note,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '说明',
            hintText: '例如：方位词，读去声',
          ),
          onChanged: (note) {
            onChanged(value.copyWith(note: note));
          },
        ),
      ],
    );
  }

  String _candidateDescription(ProsodyCalibrationCandidate candidate) {
    if (candidate.matches.isEmpty) {
      return '本地韵表暂未收录。';
    }
    final options = candidate.matches
        .map((entry) => '${entry.label}（${entry.tone == RhymeTone.level ? '平' : '仄'}）')
        .join('、');
    return '候选：$options；当前显示：${candidate.currentTone}。';
  }
}

const _toneOptions = <String>{'', '平', '仄', '多'};
