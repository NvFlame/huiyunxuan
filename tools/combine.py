# -*- coding: utf-8 -*-
import sys

with open("E:/huiyunxuan/lib/screens/learning_mode_screen.dart", "r", encoding="utf8") as f:
    head = f.read()
with open("E:/huiyunxuan/lib/screens/learning_mode_screen.tail", "r", encoding="utf8") as f:
    tail = f.read()

new_block = r"""            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Decorative title pill
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4C7),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFFE6C66A).withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.school_outlined,
                                color: const Color(0xFF9A7B2F), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '转入展才',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontFamily: kFeiHuaSongTiFontFamily,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4D3714),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Poem context
                    Center(
                      child: Text(
                        ' \u00b7 ',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7B5A00),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Section: 难度
                    Row(
                      children: [
                        Icon(Icons.trending_up_outlined,
                            size: 18, color: const Color(0xFF9A7B2F)),
                        const SizedBox(width: 6),
                        Text('难度', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<TrainingDifficulty>(
                        segments: [
                          for (final item in TrainingDifficulty.values)
                            ButtonSegment<TrainingDifficulty>(
                              value: item,
                              label: Text(item.label),
                            ),
                        ],
                        selected: {difficulty},
                        onSelectionChanged: (selected) {
                          setSheetState(() {
                            difficulty = selected.first;
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 6),
                      child: Text(
                        difficulty.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6C5523),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Section: 批改方式
                    Row(
                      children: [
                        Icon(Icons.rate_review_outlined,
                            size: 18, color: const Color(0xFF9A7B2F)),
                        const SizedBox(width: 6),
                        Text('批改方式', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<CorrectionMode>(
                        segments: [
                          for (final item in CorrectionMode.values)
                            ButtonSegment<CorrectionMode>(
                              value: item,
                              label: Text(item.label),
                            ),
                        ],
                        selected: {correctionMode},
                        onSelectionChanged: (selected) {
                          setSheetState(() {
                            correctionMode = selected.first;
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 6),
                      child: Text(
                        correctionMode.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6C5523),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Start button
                    SizedBox(
                      width: double.infinity,
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              _TrainingLaunchOptions(
                                difficulty: difficulty,
                                correctionMode: correctionMode,
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text(
                            '开始训练',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );"""

full = head.rstrip() + "\n" + new_block + "\n" + tail.lstrip()

with open("E:/huiyunxuan/lib/screens/learning_mode_screen.dart", "w", encoding="utf8") as f:
    f.write(full)

print(f"Done. Head={len(head)} Block={len(new_block)} Tail={len(tail)} Total={len(full)}")
