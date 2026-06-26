import 'package:flutter/material.dart';

import '../services/poem_fingerprint_service.dart';
import '../theme/app_typography.dart';

Future<bool> confirmPotentialDuplicatePoems({
  required BuildContext context,
  required List<DuplicatePoemCandidate> candidates,
  String title = '发现疑似重复',
}) async {
  if (candidates.isEmpty) {
    return true;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => DuplicatePoemDialog(
      title: title,
      candidates: candidates,
    ),
  );
  return confirmed == true;
}

class DuplicatePoemDialog extends StatelessWidget {
  const DuplicatePoemDialog({
    super.key,
    required this.title,
    required this.candidates,
  });

  final String title;
  final List<DuplicatePoemCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final visibleCandidates = candidates.take(8).toList(growable: false);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '程序在本地诗词库中找到了疑似同一作品。标题没有参与判断；你可以继续保存，也可以取消后核对。',
              ),
              const SizedBox(height: 12),
              for (final candidate in visibleCandidates) ...[
                _DuplicatePoemTile(candidate: candidate),
                const SizedBox(height: 8),
              ],
              if (candidates.length > visibleCandidates.length)
                Text(
                  '另有 ${candidates.length - visibleCandidates.length} 条疑似重复未显示。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('仍然继续'),
        ),
      ],
    );
  }
}

class _DuplicatePoemTile extends StatelessWidget {
  const _DuplicatePoemTile({required this.candidate});

  final DuplicatePoemCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final poem = candidate.poem;
    final collections = candidate.collectionNames.isEmpty
        ? '未归入诗词库'
        : candidate.collectionNames.join('、');
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D8),
        border: Border.all(color: const Color(0xFFE0B437)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '《${poem.title}》',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFamily: kFeiHuaSongTiFontFamily,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (poem.dynasty.trim().isNotEmpty) poem.dynasty.trim(),
              if (poem.author.trim().isNotEmpty) poem.author.trim(),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '原因：${candidate.reason}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '所在库：$collections',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
