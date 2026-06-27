import subprocess
proc = subprocess.run(["git","cat-file","-p","HEAD:lib/screens/learning_mode_screen.dart"],
    capture_output=True, cwd="E:/huiyunxuan")
orig = proc.stdout.decode("utf-8")

start = "return SafeArea("
start_idx = orig.find(start, orig.find("final theme = Theme.of(context);"))

end = "      },\n    );\n\n    if (options == null || !mounted)"
end_idx = orig.find(end, start_idx)
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
                          _buildChoiceTile(
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
                          _buildChoiceTile(
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

# Now replace _TrainingChoiceTile with inline code
# The block needs a local helper _buildChoiceTile defined inside the StatefulBuilder builder
# Let me insert it after 'final theme = Theme.of(context);' and before '\n\n            return SafeArea('

helper = """    Widget _buildChoiceTile({required String label, required bool selected, required VoidCallback onTap}) {
      final borderColor = selected ? const Color(0xFFB8841F) : const Color(0xFFE6C46B);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minWidth: 72),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFF2D68B).withOpacity(0.88)
                  : const Color(0xFFFFFCF1).withOpacity(0.72),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: borderColor, width: selected ? 1.15 : 1),
              boxShadow: selected
                  ? const [BoxShadow(color: Color(0x1CB8841F), blurRadius: 10, offset: Offset(0, 4))]
                  : [],
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? const Color(0xFF4F3B12) : const Color(0xFF3F3218),
                fontFamily: kSongTiFontFamily,
                fontFamilyFallback: kSongTiFontFallback,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      );
    }

"""

# Insert helper after 'final theme = Theme.of(context);'
helper_pos = orig.find("final theme = Theme.of(context);", start_idx - 200)
helper_pos = helper_pos + len("final theme = Theme.of(context);")

# Adjust: the helper goes inside the builder, after 'final theme = Theme.of(context);'
# The old block from start_idx to close_end will be replaced
# But we need to insert the helper before the return SafeArea

# Approach: insert helper into the new_block by finding
# 'children: [' and adding the helper as a local function call approach won't work
# Better: modify new_block to include the local function inside the StatefulBuilder

# Actually, the cleanest approach: the helper function goes inside the
# StatefulBuilder builder, BEFORE the return statement.
# But my new_block starts with 'return SafeArea('.
# The original has 'final theme = Theme.of(context);' then \n\n before 'return SafeArea('

# Let me insert the helper between 'final theme = Theme.of(context);' and the return
# Modify the original by inserting the helper after 'final theme = Theme.of(context);\n\n'

helper_insert_pos = orig.find("final theme = Theme.of(context);", helper_pos - 100)
helper_insert_pos = helper_insert_pos + len("final theme = Theme.of(context);")

# Now replace from 'return' after helper_pos to close_end
ret_start = orig.find("return SafeArea(", helper_insert_pos)
new_content = orig[:ret_start] + helper + new_block + orig[close_end:]

with open("E:/huiyunxuan/lib/screens/learning_mode_screen.dart","w",encoding="utf8") as f:
    f.write(new_content)

print("OK orig=%d new=%d" % (len(orig), len(new_content)))
