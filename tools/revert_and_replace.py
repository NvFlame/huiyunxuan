import subprocess
proc = subprocess.run(["git","cat-file","-p","HEAD:lib/screens/learning_mode_screen.dart"],
    capture_output=True, cwd="E:/huiyunxuan")
orig = proc.stdout.decode("utf-8")

start = "return SafeArea("
start_idx = orig.find(start, orig.find("final theme = Theme.of(context);"))
assert start_idx >= 0, "start not found"

end = "      },\n    );\n\n    if (options == null || !mounted)"
end_idx = orig.find(end, start_idx)
assert end_idx >= 0, "end not found"
close_end = end_idx + len("      },\n    );")

new_block = r"""return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      '转入展才',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: kFeiHuaSongTiFontFamily,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4D3714),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ' \u00b7 ',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF7B5A00),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Difficulty choices
                    Text('难度', style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF5B4B27),
                    )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in TrainingDifficulty.values)
                          _TrainingChoiceTile(
                            label: item.label,
                            selected: difficulty == item,
                            onTap: () => setSheetState(() => difficulty = item),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 8),
                      child: Text(
                        difficulty.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6C5523),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Correction mode choices
                    Text('批改方式', style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF5B4B27),
                    )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in CorrectionMode.values)
                          _TrainingChoiceTile(
                            label: item.label,
                            selected: correctionMode == item,
                            onTap: () => setSheetState(() => correctionMode = item),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 8),
                      child: Text(
                        correctionMode.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6C5523),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Start button
                    SizedBox(
                      width: double.infinity,
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );"""

new_content = orig[:start_idx] + new_block + orig[close_end:]

with open("E:/huiyunxuan/lib/screens/learning_mode_screen.dart","w",encoding="utf8") as f:
    f.write(new_content)

print("OK orig=%d new=%d" % (len(orig), len(new_content)))
