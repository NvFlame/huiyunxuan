import re
with open('E:/huiyunxuan/lib/screens/learning_mode_screen.dart', 'r', encoding='utf8') as f:
    content = f.read()

start_marker = '            return SafeArea(\n              child: Padding(\n                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),'
start_idx = content.find(start_marker)

safearea_end = '            );\n          },\n        );'
end_idx = content.find(safearea_end, start_idx + len(start_marker))
if end_idx >= 0:
    end_idx += len(safearea_end)

print(f'Start: {start_idx}, End: {end_idx}')
