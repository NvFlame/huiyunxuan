import subprocess
proc = subprocess.run(["git","cat-file","-p","HEAD:lib/screens/learning_mode_screen.dart"],
    capture_output=True, cwd="E:/huiyunxuan")
original = proc.stdout.decode("utf-8")

start = "            return SafeArea(\n              child: Padding(\n                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),"
start_idx = original.find(start)

end = "            );\n          },\n        );\n      },\n    );"
end_idx = original.find(end, start_idx) + len(end)

with open("E:/huiyunxuan/tools/bottomsheet_block.txt","r",encoding="utf8") as f:
    block = f.read()

new = original[:start_idx] + block.rstrip() + "\n" + original[end_idx:]

with open("E:/huiyunxuan/lib/screens/learning_mode_screen.dart","w",encoding="utf8") as f:
    f.write(new)

print(f"OK orig={len(original)} new={len(new)} safes={new.count('return SafeArea(')}")
